# Where the landing page's FAQ sends how long a question was open (D-094), with navigator.sendBeacon as the page goes away.
# Public: anyone reading the FAQ, signed in or not. It stores the key, the seconds and the browser's random reader ID (D-095), and nothing else about the sender.
class FaqReadsController < ApplicationController
  # sendBeacon can't add the CSRF header, and the request is no more than a key and a number from any reader, with no
  # session behind it. This is the only action that skips the check.
  skip_forgery_protection only: :create
  # The app's other public endpoints have no limit; this one takes writes, so it's capped per address (the address is
  # only the cache key for the count, never stored). Plenty for one reader, who sends a read per question.
  rate_limit to: 120, within: 1.minute, only: :create, with: -> { head :too_many_requests }

  def create
    return head :no_content if true_user&.admin? # admins leave no trace (D-032)

    head(FaqRead.record(params[:key], params[:seconds], params[:reader_id]) ? :no_content : :unprocessable_content)
  end
end
