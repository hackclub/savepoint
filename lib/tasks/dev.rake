# Made-up people for development: bin/rails dev:fake, and bin/rails dev:fake:reset to remove only them.
namespace :dev do
  desc "Add (or refresh) fake participants, buddies, ships and orders. Development only, safe to repeat."
  task fake: :environment do
    require Rails.root.join("lib/dev/fake_people")
    puts "#{Dev::FakePeople.seed!} fake people are in place."
  end

  namespace :fake do
    desc "Remove the fake participants and everything they own. Real users stay."
    task reset: :environment do
      require Rails.root.join("lib/dev/fake_people")
      puts "Removed #{Dev::FakePeople.reset!} fake people."
    end
  end
end
