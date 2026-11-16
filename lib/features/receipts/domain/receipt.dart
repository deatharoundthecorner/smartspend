/// OCR output is deliberately separate from ExpenseDraft and is never persisted
/// automatically. The future scanner UI must obtain explicit user verification.
class OcrExtraction {
  const OcrExtraction({this.amountText, this.merchantName, this.spentAt});
  final String? amountText;
  final String? merchantName;
  final DateTime? spentAt;
}

class ReceiptAttachment {
  const ReceiptAttachment({
    required this.id,
    required this.localPath,
    required this.createdAt,
    required this.verifiedAt,
  });
  final String id;
  final String localPath;
  final DateTime createdAt;
  final DateTime verifiedAt;
}
