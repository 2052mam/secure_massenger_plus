import 'package:equatable/equatable.dart';

class ReactionModel extends Equatable {
  final String emoji;
  final int count;
  final bool me;

  const ReactionModel({required this.emoji, required this.count, this.me = false});

  factory ReactionModel.fromJson(Map<String, dynamic> json) {
    return ReactionModel(
      emoji: json['emoji'] as String,
      count: json['count'] as int? ?? 1,
      me: json['me'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {'emoji': emoji, 'count': count, 'me': me};

  @override
  List<Object?> get props => [emoji, count, me];
}
