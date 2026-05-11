import 'package:flutter/material.dart';
import '../model/favorite_model.dart';

class FoodCard extends StatelessWidget {
  final Map food;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onFavoriteToggle;

  FoodCard({
    required this.food,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: Column(
        children: [

          // IMAGE + FAVORITE
          Stack(
            children: [
              Container(
                height: 100,
                width: double.infinity,
                child: Builder(
                  builder: (context) {
                    final imageUrl = food["image"]?.toString().trim() ?? '';
                    if (imageUrl.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    );
                  },
                ),
              ),

              Positioned(
                right: 8,
                top: 8,
                child: GestureDetector(
                  onTap: onFavoriteToggle,
                  child: Icon(
                    FavoriteModel.isFavorite(food["name"])
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 6),

          Text(food["name"]),
          Text("₹${food["price"]}"),

          Spacer(),

          quantity == 0
              ? ElevatedButton(
                  onPressed: onAdd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF0A1F44),
                  ),
                  child: Text("ADD"),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(onPressed: onRemove, icon: Icon(Icons.remove)),
                    Text('$quantity'),
                    IconButton(onPressed: onAdd, icon: Icon(Icons.add)),
                  ],
                ),

          SizedBox(height: 8),
        ],
      ),
    );
  }
}