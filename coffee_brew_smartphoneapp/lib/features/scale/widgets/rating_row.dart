import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/coffee_session.dart';

/// 1杯の評価（3段階）とお気に入りの入力行。
/// 評価は同じものをもう一度押すと未評価に戻る。
class RatingFavoriteRow extends StatelessWidget {
  final int? rating;
  final bool isFavorite;
  final ValueChanged<int?> onRatingChanged;
  final ValueChanged<bool> onFavoriteChanged;

  const RatingFavoriteRow({
    super.key,
    required this.rating,
    required this.isFavorite,
    required this.onRatingChanged,
    required this.onFavoriteChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final value in const [1, 2, 3])
                ChoiceChip(
                  label: Text(CoffeeSession.ratingLabel(value)),
                  selected: rating == value,
                  selectedColor: BrewColors.oat,
                  onSelected: (_) =>
                      onRatingChanged(rating == value ? null : value),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: isFavorite ? 'お気に入りを外す' : 'お気に入りにする',
          onPressed: () => onFavoriteChanged(!isFavorite),
          icon: Icon(
            isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
            color: isFavorite ? BrewColors.amber : BrewColors.mocha,
            size: 28,
          ),
        ),
      ],
    );
  }
}
