require "test_helper"

class AdminMcp::SqlGuardTest < ActiveSupport::TestCase
  SCHEMAS = %w[public insights pg_catalog information_schema].freeze
  SCHEMA_MESSAGE = "Only the insights schema is readable here, not public."

  def refusal(sql) = assert_raises(AdminMcp::SqlGuard::Refused) { AdminMcp::SqlGuard.check(sql, schemas: SCHEMAS) }

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
