# Makes the Airtable tables and fields the sync writes (D-027). Only adds, never
# deletes or renames. Needs AIRTABLE_PROGRAM_TOKEN with schema.bases:read and :write.
#
#   bin/rails airtable:provision:plan   # prints the plan, no token, no API call
#   bin/rails airtable:provision        # creates what is missing, prints it
namespace :airtable do
  desc "Create the missing Airtable tables and fields"
  task provision: :environment do
    provisioner = AirtableProvisioner.new(client: AirtableClient.new)
    steps = provisioner.run
    puts "Nothing to create. The base is up to date." if steps.empty? && provisioner.failures.empty?
    steps.each { puts AirtableProvisioner.describe(it) }
    provisioner.failures.each { |step, message| warn "FAILED #{AirtableProvisioner.describe(step)}: #{message}" }
    abort "#{provisioner.failures.size} step(s) failed. Run it again after fixing them." if provisioner.failures.any?
  end

  namespace :provision do
    desc "Print what airtable:provision would make in an empty base"
    task plan: :environment do
      puts "Base #{Rails.application.config_for(:airtable)[:base]}. An existing table or field is skipped when you run it."
      AirtableProvisioner.new.plan.each { puts AirtableProvisioner.describe(it) }
      AirtableSchema::TABLES.each do |key, defs|
        puts "\n#{Rails.application.config_for(:airtable)[:tables][key]}"
        defs.each { |name, type, options| puts "  #{name}: #{type}#{" #{options.to_json}" if options}" }
      end
    end
  end
end
