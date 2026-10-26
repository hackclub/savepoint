class RandomizeBuddyCodes < ActiveRecord::Migration[8.1]
  # Invite codes used to be people's first names (/b/kartikey), which told anyone with the link who sent it. Every
  # existing code becomes random, so old invite links stop working; people's buddy pages show their new one.
  def up
    select_values("SELECT id FROM projects WHERE buddy_code IS NOT NULL").each do |id|
      code = loop do
        candidate = SecureRandom.alphanumeric(8).downcase
        break candidate unless select_value("SELECT 1 FROM projects WHERE buddy_code = #{quote(candidate)}")
      end
      execute "UPDATE projects SET buddy_code = #{quote(code)} WHERE id = #{id.to_i}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
