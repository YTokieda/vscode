ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # テスト用の領収書を作る。読み取り済みの状態がほしいときは attrs で上書きする
    def create_receipt(filename: "receipt.png", content_type: "image/png", **attrs)
      receipt = Receipt.new(attrs)
      receipt.file.attach(io: file_fixture(filename).open, filename: filename, content_type: content_type)
      receipt.save!
      receipt
    end

    def create_extracted_receipt(**attrs)
      create_receipt(status: "extracted", transaction_date: Date.new(2026, 3, 5), vendor: "文具のミドリ",
                     amount: 1100, account_item: "消耗品費", description: "ボールペン", **attrs)
    end
  end
end
