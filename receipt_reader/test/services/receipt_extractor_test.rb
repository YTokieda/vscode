require "test_helper"
require "socket"

class ReceiptExtractorTest < ActiveSupport::TestCase
  # 本物のAPIを呼ばずに試すための「にせもの」のクライアント。
  # client.beta.messages.create(...) の呼び出しを記録し、決めておいた返事を返す。
  class FakeClient
    attr_reader :requests

    def initialize(json: nil, stop_reason: :end_turn)
      @json = json
      @stop_reason = stop_reason
      @requests = []
    end

    def beta = self
    def messages = self

    def create(**params)
      @requests << params
      blocks = [ Struct.new(:type).new(:thinking) ]
      blocks << Struct.new(:type, :text).new(:text, @json.to_json) if @json
      Struct.new(:stop_reason, :content).new(@stop_reason, blocks)
    end
  end

  RESULT = {
    "is_receipt" => true, "transaction_date" => "2026-02-14", "vendor" => "喫茶ひだまり",
    "total_amount" => 1650, "reduced_rate_amount" => 0, "main_tax_rate" => 10, "entry_side" => "支出",
    "description" => "コーヒー2杯", "invoice_number" => "T9876543210987", "suggested_account" => "会議費",
    "reason" => "2人分の飲み物で打ち合わせと思われるため。私用なら事業主貸です。", "warnings" => [ "人数が読み取れません" ]
  }.freeze

  test "画像を送って、読み取り結果を保存する" do
    client = FakeClient.new(json: RESULT)
    receipt = ReceiptExtractor.new(client: client).call(create_receipt)

    assert receipt.extracted?
    assert_equal Date.new(2026, 2, 14), receipt.transaction_date
    assert_equal "喫茶ひだまり", receipt.vendor
    assert_equal 1650, receipt.amount
    assert_equal "会議費", receipt.account_item
    assert_equal "T9876543210987", receipt.invoice_number
    assert_equal [ "人数が読み取れません" ], receipt.warnings_list
    assert_match "事業主貸", receipt.ai_reason

    request = client.requests.first
    content = request[:messages].first[:content]
    assert_equal "image", content.first[:type]
    assert_equal "image/png", content.first[:source][:media_type]
    assert_equal :json_schema, request[:output_config][:format][:type]
  end

  test "PDFは document として送る" do
    client = FakeClient.new(json: RESULT)
    ReceiptExtractor.new(client: client).call(create_receipt(filename: "invoice.pdf", content_type: "application/pdf"))
    assert_equal "document", client.requests.first[:messages].first[:content].first[:type]
  end

  test "読めなかった項目は空のまま、領収書でなければ注意を残す" do
    result = RESULT.merge("is_receipt" => false, "transaction_date" => nil, "vendor" => nil, "total_amount" => nil, "warnings" => [])
    receipt = ReceiptExtractor.new(client: FakeClient.new(json: result)).call(create_receipt)

    assert receipt.extracted?
    assert_nil receipt.transaction_date
    assert_not receipt.complete?
    assert_equal [ "領収書・請求書ではない可能性があります" ], receipt.warnings_list
  end

  test "8%対象額が合計を超えていたら0に戻して注意を残す" do
    result = RESULT.merge("total_amount" => 500, "reduced_rate_amount" => 800)
    receipt = ReceiptExtractor.new(client: FakeClient.new(json: result)).call(create_receipt)
    assert receipt.extracted?
    assert_equal 0, receipt.reduced_rate_amount
    assert_match "軽減税率", receipt.ai_warnings
  end

  test "AIが断ったら失敗として理由を残す" do
    receipt = ReceiptExtractor.new(client: FakeClient.new(stop_reason: :refusal)).call(create_receipt)
    assert receipt.failed?
    assert_match "断りました", receipt.error_message
  end

  test "APIキーがなければ失敗として理由を残す" do
    original = ENV.delete("ANTHROPIC_API_KEY")
    receipt = ReceiptExtractor.new.call(create_receipt)
    assert receipt.failed?
    assert_match "ANTHROPIC_API_KEY", receipt.error_message
  ensure
    ENV["ANTHROPIC_API_KEY"] = original if original
  end

  # 本物の Anthropic gem を使い、手元に立てた仮のサーバーに送らせて、
  # 実際にAPIへ送られる中身（JSONとヘッダ）が正しい形かを確かめる。
  test "本物のSDKが正しい形のリクエストを作る" do
    server = TCPServer.new("127.0.0.1", 0)
    captured = {}
    thread = Thread.new do
      socket = server.accept
      head = +""
      head << socket.gets until head.end_with?("\r\n\r\n")
      length = head[/content-length: (\d+)/i, 1].to_i
      captured[:headers] = head
      captured[:body] = JSON.parse(socket.read(length))
      reply = {
        id: "msg_test", type: "message", role: "assistant", model: "claude-opus-5-5",
        content: [ { type: "text", text: RESULT.to_json } ], stop_reason: "end_turn", stop_sequence: nil,
        usage: { input_tokens: 10, output_tokens: 10 }
      }.to_json
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{reply.bytesize}\r\nConnection: close\r\n\r\n#{reply}")
      socket.close
    end

    client = Anthropic::Client.new(api_key: "test-key", base_url: "http://127.0.0.1:#{server.addr[1]}", max_retries: 0)
    data = ReceiptExtractor.new(client: client).extract(file_fixture("receipt.png").binread, "image/png")
    thread.join(5)

    assert_equal "喫茶ひだまり", data["vendor"]
    body = captured[:body]
    assert_equal "claude-opus-5-5", body["model"]
    assert_equal "default", body["fallbacks"]
    assert_equal "json_schema", body.dig("output_config", "format", "type")
    assert_equal "medium", body.dig("output_config", "effort")
    assert_equal %w[is_receipt transaction_date vendor total_amount reduced_rate_amount main_tax_rate entry_side description invoice_number suggested_account reason warnings],
                 body.dig("output_config", "format", "schema", "required")
    assert_equal "base64", body.dig("messages", 0, "content", 0, "source", "type")
    assert_kind_of String, body["system"]
    assert_match(/anthropic-beta: server-side-fallback-2026-07-01/i, captured[:headers])
  ensure
    server&.close
  end
end
