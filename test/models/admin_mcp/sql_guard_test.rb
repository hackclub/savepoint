require "test_helper"

class AdminMcp::SqlGuardTest < ActiveSupport::TestCase
  SCHEMAS = %w[public insights pg_catalog information_schema].freeze
  SCHEMA_MESSAGE = "Only the insights schema is readable here, not public."

  def refusal(sql) = assert_raises(AdminMcp::SqlGuard::Refused) { AdminMcp::SqlGuard.check(sql, schemas: SCHEMAS) }

  test "the whole to_xml function family is refused" do
    %w[query_to_xmlschema table_to_xmlschema cursor_to_xmlschema schema_to_xmlschema database_to_xmlschema query_to_xml_and_xmlschema
       table_to_xml_and_xmlschema some_new_to_xml_thing].each do |name|
      assert_match(/#{name}\(\) is not allowed/, refusal("select #{name}('select 1', true, false, '')").message)
    end
  end

  test "a comment ended by a carriage return does not hide the query after it" do
    error = refusal("select 1 as a --\r, (select count(*) from public.users) as b")
    assert_equal SCHEMA_MESSAGE, error.message
  end

  test "a comment ended by a line feed does not hide the query after it" do
    error = refusal("select 1 as a --\n, (select count(*) from public.users) as b")
    assert_equal SCHEMA_MESSAGE, error.message
  end

  test "a comment ended by a carriage return and a line feed does not hide a function after it" do
    error = refusal("select 1 --\r\n, pg_read_file('/x')")
    assert_match(/pg_read_file/, error.message)
  end

  test "a comment ends at the first carriage return or line feed" do
    assert_match(/pg_read_file/, refusal("select 1 -- note\r, pg_read_file('/x')").message)
    assert_match(/pg_read_file/, refusal("select 1 -- note\n, pg_read_file('/x')").message)
    assert_match(/pg_read_file/, refusal("select 1 -- note\r\r\n, pg_read_file('/x')").message)
  end

  test "a harmless comment still passes" do
    assert_equal "select 1 -- a note", AdminMcp::SqlGuard.check("select 1 -- a note\n", schemas: SCHEMAS)
    assert_equal "select 1 -- a note", AdminMcp::SqlGuard.check("select 1 -- a note\r", schemas: SCHEMAS)
    assert_equal "select 1 -- a note\r\n, 2", AdminMcp::SqlGuard.check("select 1 -- a note\r\n, 2", schemas: SCHEMAS)
  end
end
