class CheckJameGamSubmissions < ActiveRecord::Migration[8.1]
  # D-066: one pass over everyone with a tracking project after deploy. Each job rebuilds the person's days if a submission moves
  # their start. Without the token it does nothing and the half-hourly sweep tries again.
  def up
    JameGamSweepJob.perform_later
  end

  def down
    # Nothing to undo: the jobs only read the jame gam base.
  end
end
