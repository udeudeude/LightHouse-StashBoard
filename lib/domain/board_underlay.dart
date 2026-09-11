enum BoardUnderlay {
  none(0, 0),
  grid3x3(3, 3),
  grid3x4(3, 4),
  grid4x4(4, 4),
  grid5x5(5, 5),
  grid5x6(5, 6),
  martianChess2(4, 8),
  chess8x8(8, 8);

  const BoardUnderlay(this.columns, this.rows);

  final int columns;
  final int rows;

  bool get isVisible => columns > 0 && rows > 0;

  bool get isChessLike =>
      this == BoardUnderlay.martianChess2 || this == BoardUnderlay.chess8x8;

  static BoardUnderlay fromName(Object? value) {
    if (value is! String) return BoardUnderlay.none;
    for (final underlay in BoardUnderlay.values) {
      if (underlay.name == value) return underlay;
    }
    return BoardUnderlay.none;
  }
}
