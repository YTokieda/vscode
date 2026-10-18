# アップロードされた領収書を裏側（バックグラウンド）で読み取るジョブ。
# 1枚に数秒〜十数秒かかるので、画面を待たせないようにジョブにしている。
class ExtractReceiptJob < ApplicationJob
  queue_as :default

  def perform(receipt)
    ReceiptExtractor.new.call(receipt)
  end
end
