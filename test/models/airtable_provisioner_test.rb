require "test_helper"

class AirtableProvisionerTest < ActiveSupport::TestCase
  class FakeMeta
    attr_reader :calls

    attr_accessor :fail_names

    def initialize(tables)
      @tables = tables
      @calls = []
      @fail_names = []
    end

    def tables = @tables

    def create_table(name, fields)
      raise AirtableClient::Error, "Airtable answered 422 INVALID_TABLE_NAME" if fail_names.include?(name)
      @calls << [ :table, name, fields.map { it[:name] } ]
      { "id" => "tbl#{name}", "name" => name }
    end

    def create_field(table_id, field)
      raise AirtableClient::Error, "Airtable answered 422 DUPLICATE_OR_EMPTY_FIELD_NAME" if fail_names.include?(field[:name])
      @calls << [ :field, table_id, field[:name], field[:type], field[:options] ]
    end
  end

  test "the plan needs no token and no API call" do
    ENV.delete("AIRTABLE_PROGRAM_TOKEN")
    plan = AirtableProvisioner.new.plan
    assert_equal %i[users projects orders], plan.select { it.kind == :table }.map(&:table)
    assert plan.any? { it.table == :ships && it.field == "Code URL" }
  end

  test "creates the missing tables and only the missing fields, and deletes nothing" do
    existing = [ { "id" => "tblvPYnH7OouAeFkC", "name" => "YSWS Project Submission", "fields" => [ { "name" => "Code URL" }, { "name" => "Something Else" } ] },
                { "id" => "tblUsers", "name" => "Users", "fields" => AirtableSchema.field_names(:users).map { { "name" => it } } } ]
    meta = FakeMeta.new(existing)
    done = AirtableProvisioner.new(client: meta).run
    tables = meta.calls.select { it.first == :table }
    assert_equal %w[Projects Orders], tables.map { it[1] }
    assert_equal "save_point_id", tables.first[2].first, "the id field is the first, so the primary one"
    fields = meta.calls.select { it.first == :field }
    assert_equal [ "tblvPYnH7OouAeFkC" ], fields.map { it[1] }.uniq
    assert_not_includes fields.map { it[2] }, "Code URL"
    assert_includes fields.map { it[2] }, "save_point_id"
    birthday = fields.find { it[2] == "Birthday" }
    assert_equal [ "date", { dateFormat: { name: "iso" } } ], birthday.values_at(3, 4)
    assert_equal 2 + fields.size, done.size
  end

  test "a second run with everything in place creates nothing" do
    existing = AirtableSchema::TABLES.map do |key, defs|
      { "id" => (key == :ships ? "tblvPYnH7OouAeFkC" : "tbl#{key}"), "name" => Rails.application.config_for(:airtable)[:tables][key], "fields" => defs.map { { "name" => it.first } } }
    end
    meta = FakeMeta.new(existing)
    assert_empty AirtableProvisioner.new(client: meta).run
    assert_empty meta.calls
  end

  test "names match without regard to case, so a renamed-by-case table or field is not made again" do
    users = AirtableSchema.field_names(:users).map { { "name" => it.upcase } }
    existing = [ { "id" => "tblU", "name" => "users", "fields" => users } ]
    meta = FakeMeta.new(existing)
    AirtableProvisioner.new(client: meta).run
    assert_not_includes meta.calls.select { it.first == :table }.map { it[1] }, "Users"
    assert_empty meta.calls.select { it.first == :field && it[1] == "tblU" }
  end

  test "a step that fails is kept, the rest still run, and the failures are listed" do
    meta = FakeMeta.new([ { "id" => "tblvPYnH7OouAeFkC", "name" => "YSWS Project Submission", "fields" => [] } ])
    meta.fail_names = [ "Projects", "Birthday" ]
    provisioner = AirtableProvisioner.new(client: meta)
    done = provisioner.run
    assert_equal [ [ :projects, nil ], [ :ships, "Birthday" ] ], provisioner.failures.map { |step, _| [ step.table, step.field ] }
    assert_match "INVALID_TABLE_NAME", provisioner.failures.first.last
    assert_includes meta.calls.map { it[1] }, "Orders", "a later table still ran"
    assert_includes meta.calls.map { it[2] }, "Justification - Submitter Hackatime ID", "a later field still ran"
    assert_not_includes done.map(&:field), "Birthday"
  end
end
