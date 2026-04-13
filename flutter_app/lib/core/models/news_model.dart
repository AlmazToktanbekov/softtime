class News {
  final String id;
  final String title;
  final String content;
  final String type;
  final String? imageUrl;
  final String targetAudience;
  final bool pinned;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;

  News({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    this.imageUrl,
    required this.targetAudience,
    required this.pinned,
    this.createdBy,
    required this.createdAt,
    this.updatedAt,
  });

  factory News.fromJson(Map<String, dynamic> json) => News(
        id: json['id'].toString(),
        title: json['title'] as String,
        content: json['content'] as String,
        type: json['type'].toString(),
        imageUrl: json['image_url']?.toString(),
        targetAudience: json['target_audience'].toString(),
        pinned: json['pinned'] as bool,
        createdBy: json['created_by']?.toString(),
        createdAt: DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now(),
        updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
      );
}
