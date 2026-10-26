# Makes the tables and fields in AirtableSchema, with the meta API. It only
# adds: it never deletes, renames or changes a table or a field. A table or field
# that exists is left as it is. The submission table is found by its id (config
# submission_table_id), the others by name.
class AirtableProvisioner
  Step = Data.define(:table, :field, :kind) # kind: :table or :field

  # One line for a step, by table and field name.
  def self.describe(step)
    table = Rails.application.config_for(:airtable)[:tables].fetch(step.table)
    step.kind == :table ? "create table #{table} with #{AirtableSchema.field_names(step.table).size} fields" : "create field #{table} / #{step.field}"
  end

  def initialize(client: nil, config: Rails.application.config_for(:airtable))
    @client = client
    @config = config
  end

  # What a run would do against a base with only the submission table, with no API call.
  def plan
    table = @config[:submission_table_id]
    steps(existing: table.present? ? [ { "id" => table, "name" => @config[:tables][:ships], "fields" => [] } ] : [])
  end

  # Steps that Airtable refused, as [step, error message]. Set by run.
  attr_reader :failures

  # Does the work and returns the steps it took. A step that fails is kept in failures and the rest still run.
  def run
    @failures = []
    existing = @client.tables
    steps(existing:).each_with_object([]) do |step, done|
      fields = AirtableSchema.field_defs(step.table)
      if step.kind == :table
        created = @client.create_table(@config[:tables].fetch(step.table), fields)
        # Fields now on the new table are not made again.
        existing << created.slice("id", "name").merge("fields" => fields.map { { "name" => it[:name] } })
      else
        found = find(existing, step.table)
        @client.create_field(found.fetch("id"), fields.find { it[:name] == step.field })
        found["fields"] << { "name" => step.field }
        sleep 0.25 unless Rails.env.test?
      end
      done << step
    rescue AirtableClient::Error => e
      @failures << [ step, e.message ]
    end
  end

  private

  def steps(existing:)
    AirtableSchema::TABLES.flat_map do |key, defs|
      found = find(existing, key)
      if found.nil?
        [ Step.new(key, nil, :table) ]
      else
        have = found["fields"].map { it["name"] }
        defs.map(&:first).reject { |name| have.any? { it.casecmp?(name) } }.map { Step.new(key, it, :field) }
      end
    end
  end

  def find(existing, key)
    if key == :ships && @config[:submission_table_id].present?
      existing.find { it["id"] == @config[:submission_table_id] } ||
        existing.find { it["name"].to_s.casecmp?(@config[:tables].fetch(key)) }
    else
      existing.find { it["name"].to_s.casecmp?(@config[:tables].fetch(key)) }
    end
  end
end
