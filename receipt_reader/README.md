# 領収書読み取り（receipt_reader）

領収書・レシート・請求書の **画像やPDF** から、AI（Claude API）で **日付・金額・取引先** などを読み取り、
**一覧CSV（Excel用）** と **freee会計の取引インポート用CSV** で出力する Rails アプリです。
個人事業主の確定申告の記帳を楽にすることを目標にしています。

## できること

1. 画像（JPEG・PNG・GIF・WebP）やPDFをまとめてアップロード
2. AIが次の項目を読み取る
   - 日付、取引先、税込の合計金額
   - 軽減税率8%の対象額（スーパーのレシートなど、8%と10%が混ざるもの）
   - 消費税の対象外かどうか（切手・印紙など）
   - インボイス登録番号（T＋13桁）
   - 勘定科目の候補と **その科目を選んだ理由**、読み取りに自信がない点
3. 元の画像を見ながら画面で確認・修正
4. 年ごとに絞り込んで CSV をダウンロード
   - 一覧CSV: UTF-8（BOM付き）なので Excel でそのまま開けます
   - freee用CSV: 「取引・口座振替のインポート」の列に合わせた形式。8%と10%が混ざった領収書は税率ごとに別の取引として出します

## 動かし方

Ruby 3.3 が入っている前提です。

```bash
cd receipt_reader
bundle install
bin/rails db:prepare

# Claude API のキー（https://console.anthropic.com/ で発行）
export ANTHROPIC_API_KEY="sk-ant-..."

bin/rails server
```

ブラウザで http://localhost:3000 を開きます。
APIキーなしで画面だけ見たいときは `bin/rails db:seed` でサンプルデータが入ります。

テストは `bin/rails test` で実行できます（本物のAPIは呼びません）。

## しくみ（コードの読みどころ）

| ファイル | 役割 |
| --- | --- |
| `app/models/receipt.rb` | 領収書1枚分のデータ。ファイル形式のチェック、税率ごとの内訳の計算 |
| `app/services/receipt_extractor.rb` | **AIを呼ぶ部分**。ファイルを Base64 にして Claude API に送り、JSON で結果を受け取る |
| `app/jobs/extract_receipt_job.rb` | 読み取りを裏側で動かすジョブ（1枚に数秒〜十数秒かかるため） |
| `app/services/freee_csv_exporter.rb` | freee 取引インポート用CSVを作る |
| `app/services/receipt_csv_exporter.rb` | Excel 用の一覧CSVを作る |
| `app/controllers/receipts_controller.rb` | 画面の処理（アップロード・修正・CSVダウンロード） |

AIの使い方のポイントは `receipt_extractor.rb` にあります。

- **画像は `image`、PDFは `document`** というブロックで送ります。PDFは文字だけでなくページの見た目も読まれます。
- **構造化出力（`output_config.format`）** で JSON Schema を指定しています。返答がスキーマどおりのJSONになることが保証されるので、
  文章から数字を探すような不安定な処理が不要です。項目を増やしたいときは `SCHEMA` と `SYSTEM_PROMPT` に足します。
- 読めない項目は「推測で埋めず null にする」ようプロンプトで指示し、確認が必要な点を `warnings` で返させています。
  確定申告に使う以上、**最後は人が確認する** 前提の作りです。

### モデルと料金

既定のモデルは `claude-opus-5-5`（入力 $4／出力 $20、100万トークンあたり）です。領収書1枚あたりの費用は画像の大きさや
AIが考える量で変わるので、最初の数枚を試したら [Console](https://console.anthropic.com/) の利用量で確認してください。
環境変数で変えられます。

```bash
export CLAUDE_MODEL="claude-sonnet-5-5"   # 安いモデルにする
export CLAUDE_EFFORT="low"                # 考える量を減らす（low / medium / high）
```

## freee に取り込むときの注意

- 列の並びは freee の「[取引・口座振替のインポート（一括登録）](https://support.freee.co.jp/hc/ja/articles/202847320)」の
  サンプルファイルに合わせています。開発環境から freee のヘルプページを直接開けなかったため、**最初は1〜2件だけで取り込みを試し**、
  サンプルのヘッダと見比べてください。違っていたら `FreeeCsvExporter::HEADERS` を直せば合わせられます。
- **決済口座** は freee に登録してある口座名と一字一句同じにします（例: `現金`、個人事業主なら `プライベート資金`）。
  空にすると「未決済」の取引になります。
- 税区分は `課対仕入10%`・`課対仕入8%（軽）`・`対象外` を使っています。freee 側の表記と違うとエラーになるので、
  取り込みでエラーが出たら `FreeeCsvExporter::TAX_CATEGORIES` を確認してください。
- 取引先・勘定科目は freee にない名前だと自動で作られることがあります。勘定科目は freee にある名前に直してから出力するのが安全です。
- freee 自体にも、スマホで撮った領収書をOCRで読み取って取引登録する機能（ファイルボックス）があります。
  このアプリは「AIが科目の理由や注意点を説明する」「Excel用一覧も同時に作る」「freee以外にも使えるCSVにする」ところに違いがあります。

## 今後の改善案

- 電子帳簿保存法に合わせた保存（検索できる形で原本を保管）
- マネーフォワード・弥生のインポート形式
- 過去に直した科目を覚えて、同じ取引先なら同じ科目を提案する
- 複数ページのPDFに複数の領収書が入っている場合の分割
