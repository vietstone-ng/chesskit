import 'dart:math' as math;

import 'package:fast_immutable_collections/fast_immutable_collections.dart'
    hide Tuple2;
import 'package:meta/meta.dart';

import './board.dart';
import './constants.dart';
import './models.dart';
import './square_set.dart';
import './utils.dart';

/// A not necessarily legal position.
@immutable
class Setup {
  /// Piece positions on the board.
  final Board board;

  /// Pockets in chess variants like [Crazyhouse].
  final Pockets? pockets;

  /// Side to move.
  final Side turn;

  /// Unmoved rooks positions used to determine castling rights.
  final SquareSet unmovedRooks;

  /// En passant target square.
  ///
  /// Valid target squares are on the third or sixth rank.
  final Square? epSquare;

  /// Number of half-moves since the last capture or pawn move.
  final int halfmoves;

  /// Current move number.
  final int fullmoves;

  /// Number of remainingChecks for white (`item1`) and black (`item2`).
  final Tuple2<int, int>? remainingChecks;

  const Setup({
    required this.board,
    this.pockets,
    required this.turn,
    required this.unmovedRooks,
    this.epSquare,
    required this.halfmoves,
    required this.fullmoves,
    this.remainingChecks,
  });

  static const Setup standard = Setup(
    board: Board.standard,
    turn: Side.white,
    unmovedRooks: SquareSet.corners,
    halfmoves: 0,
    fullmoves: 1,
  );

  /// Parse Forsyth-Edwards-Notation and returns a Setup.
  ///
  /// The parser is relaxed:
  ///
  /// * Supports X-FEN and Shredder-FEN for castling right notation.
  /// * Accepts missing FEN fields (except the board) and fills them with
  ///   default values of `8/8/8/8/8/8/8/8 w - - 0 1`.
  /// * Accepts multiple spaces and underscores (`_`) as separators between
  ///   FEN fields.
  ///
  /// Throws a [FenError] if the provided FEN is not valid.
  factory Setup.parseFen(String fen) {
    final List<String> parts = fen.split(RegExp(r'[\s_]+'));
    if (parts.isEmpty) throw const FenError('ERR_FEN');

    // board and pockets
    final String boardPart = parts.removeAt(0);
    Pockets? pockets;
    Board board;
    if (boardPart.endsWith(']')) {
      final int pocketStart = boardPart.indexOf('[');
      if (pocketStart == -1) {
        throw const FenError('ERR_FEN');
      }
      board = Board.parseFen(boardPart.substring(0, pocketStart));
      pockets = _parsePockets(
        boardPart.substring(pocketStart + 1, boardPart.length - 1),
      );
    } else {
      final int pocketStart = _nthIndexOf(boardPart, '/', 7);
      if (pocketStart == -1) {
        board = Board.parseFen(boardPart);
      } else {
        board = Board.parseFen(boardPart.substring(0, pocketStart));
        pockets = _parsePockets(boardPart.substring(pocketStart + 1));
      }
    }

    // turn
    Side turn;
    if (parts.isEmpty) {
      turn = Side.white;
    } else {
      final String turnPart = parts.removeAt(0);
      if (turnPart == 'w') {
        turn = Side.white;
      } else if (turnPart == 'b') {
        turn = Side.black;
      } else {
        throw const FenError('ERR_TURN');
      }
    }

    // Castling
    SquareSet unmovedRooks;
    if (parts.isEmpty) {
      unmovedRooks = SquareSet.empty;
    } else {
      final String castlingPart = parts.removeAt(0);
      unmovedRooks = _parseCastlingFen(board, castlingPart);
    }

    // En passant square
    Square? epSquare;
    if (parts.isNotEmpty) {
      final String epPart = parts.removeAt(0);
      if (epPart != '-') {
        epSquare = parseSquare(epPart);
        if (epSquare == null) throw const FenError('ERR_EP_SQUARE');
      }
    }

    // move counters or remainingChecks
    String? halfmovePart = parts.isNotEmpty ? parts.removeAt(0) : null;
    Tuple2<int, int>? earlyRemainingChecks;
    if (halfmovePart != null && halfmovePart.contains('+')) {
      earlyRemainingChecks = _parseRemainingChecks(halfmovePart);
      halfmovePart = parts.isNotEmpty ? parts.removeAt(0) : null;
    }
    final int? halfmoves =
        halfmovePart != null ? _parseSmallUint(halfmovePart) : 0;
    if (halfmoves == null) {
      throw const FenError('ERR_HALFMOVES');
    }

    final String? fullmovesPart = parts.isNotEmpty ? parts.removeAt(0) : null;
    final int? fullmoves =
        fullmovesPart != null ? _parseSmallUint(fullmovesPart) : 1;
    if (fullmoves == null) {
      throw const FenError('ERR_FULLMOVES');
    }

    final String? remainingChecksPart =
        parts.isNotEmpty ? parts.removeAt(0) : null;
    Tuple2<int, int>? remainingChecks;
    if (remainingChecksPart != null) {
      if (earlyRemainingChecks != null) {
        throw const FenError('ERR_REMAINING_CHECKS');
      }
      remainingChecks = _parseRemainingChecks(remainingChecksPart);
    } else if (earlyRemainingChecks != null) {
      remainingChecks = earlyRemainingChecks;
    }

    if (parts.isNotEmpty) {
      throw const FenError('ERR_FEN');
    }

    return Setup(
      board: board,
      pockets: pockets,
      turn: turn,
      unmovedRooks: unmovedRooks,
      epSquare: epSquare,
      halfmoves: halfmoves,
      fullmoves: fullmoves,
      remainingChecks: remainingChecks,
    );
  }

  String get turnLetter => turn.name[0];

  String get fen => <Object>[
        board.fen + (pockets != null ? _makePockets(pockets!) : ''),
        turnLetter,
        _makeCastlingFen(board, unmovedRooks),
        if (epSquare != null) toAlgebraic(epSquare!) else '-',
        if (remainingChecks != null) _makeRemainingChecks(remainingChecks!),
        math.max(0, math.min(halfmoves, 9999)),
        math.max(1, math.min(fullmoves, 9999)),
      ].join(' ');

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Setup &&
            other.board == board &&
            other.turn == turn &&
            other.unmovedRooks == unmovedRooks &&
            other.epSquare == epSquare &&
            other.halfmoves == halfmoves &&
            other.fullmoves == fullmoves;
  }

  @override
  int get hashCode => Object.hash(
        board,
        turn,
        unmovedRooks,
        epSquare,
        halfmoves,
        fullmoves,
      );
}

/// Pockets (captured pieces) in chess variants like [Crazyhouse].
@immutable
class Pockets {
  const Pockets({
    required this.value,
  });

  final BySide<ByRole<int>> value;

  /// An empty pocket.
  static const Pockets empty = Pockets(value: _emptyPocketsBySide);

  /// Gets the total number of pieces in the pocket.
  int get size => value.values.fold(
        0,
        (int acc, ByRole<int> e) =>
            acc + e.values.fold(0, (int acc, int e) => acc + e),
      );

  /// Gets the number of pieces of that [Side] and [Role] in the pocket.
  int of(Side side, Role role) {
    return value[side]![role]!;
  }

  /// Counts the number of pieces by [Role].
  int count(Role role) {
    return value[Side.white]![role]! + value[Side.black]![role]!;
  }

  /// Checks whether this side has at least 1 quality (any piece but a pawn).
  bool hasQuality(Side side) {
    final IMap<Role, int> bySide = value[side]!;
    return bySide[Role.knight]! > 0 ||
        bySide[Role.bishop]! > 0 ||
        bySide[Role.rook]! > 0 ||
        bySide[Role.queen]! > 0 ||
        bySide[Role.king]! > 0;
  }

  /// Checks whether this side has at least 1 pawn.
  bool hasPawn(Side side) {
    return value[side]![Role.pawn]! > 0;
  }

  /// Increments the number of pieces in the pocket of that [Side] and [Role].
  Pockets increment(Side side, Role role) {
    final IMap<Role, int> newPocket =
        value[side]!.add(role, of(side, role) + 1);
    return Pockets(value: value.add(side, newPocket));
  }

  /// Decrements the number of pieces in the pocket of that [Side] and [Role].
  Pockets decrement(Side side, Role role) {
    final IMap<Role, int> newPocket =
        value[side]!.add(role, of(side, role) - 1);
    return Pockets(value: value.add(side, newPocket));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is Pockets && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

Pockets _parsePockets(String pocketPart) {
  if (pocketPart.length > 64) {
    throw const FenError('ERR_POCKETS');
  }
  Pockets pockets = Pockets.empty;
  for (int i = 0; i < pocketPart.length; i++) {
    final String c = pocketPart[i];
    final Piece? piece = Piece.fromChar(c);
    if (piece == null) {
      throw const FenError('ERR_POCKETS');
    }
    pockets = pockets.increment(piece.color, piece.role);
  }
  return pockets;
}

Tuple2<int, int> _parseRemainingChecks(String part) {
  final List<String> parts = part.split('+');
  if (parts.length == 3 && parts[0] == '') {
    final int? white = _parseSmallUint(parts[1]);
    final int? black = _parseSmallUint(parts[2]);
    if (white == null || white > 3 || black == null || black > 3) {
      throw const FenError('ERR_REMAINING_CHECKS');
    }
    return Tuple2<int, int>(3 - white, 3 - black);
  } else if (parts.length == 2) {
    final int? white = _parseSmallUint(parts[0]);
    final int? black = _parseSmallUint(parts[1]);
    if (white == null || white > 3 || black == null || black > 3) {
      throw const FenError('ERR_REMAINING_CHECKS');
    }
    return Tuple2<int, int>(white, black);
  } else {
    throw const FenError('ERR_REMAINING_CHECKS');
  }
}

SquareSet _parseCastlingFen(Board board, String castlingPart) {
  SquareSet unmovedRooks = SquareSet.empty;
  if (castlingPart == '-') {
    return unmovedRooks;
  }
  for (int i = 0; i < castlingPart.length; i++) {
    final String c = castlingPart[i];
    final String lower = c.toLowerCase();
    final Side color = c == lower ? Side.black : Side.white;
    final SquareSet backrankMask = SquareSet.backrankOf(color);
    final SquareSet backrank = backrankMask & board.bySide(color);

    Iterable<Square> candidates;
    if (lower == 'q') {
      candidates = backrank.squares;
    } else if (lower == 'k') {
      candidates = backrank.squaresReversed;
    } else if ('a'.compareTo(lower) <= 0 && lower.compareTo('h') <= 0) {
      candidates =
          (SquareSet.fromFile(lower.codeUnitAt(0) - 'a'.codeUnitAt(0)) &
                  backrank)
              .squares;
    } else {
      throw const FenError('ERR_CASTLING');
    }
    for (final Square square in candidates) {
      if (board.kings.has(square)) break;
      if (board.rooks.has(square)) {
        unmovedRooks = unmovedRooks.withSquare(square);
        break;
      }
    }
  }
  if ((const SquareSet.fromRank(0) & unmovedRooks).size > 2 ||
      (const SquareSet.fromRank(7) & unmovedRooks).size > 2) {
    throw const FenError('ERR_CASTLING');
  }
  return unmovedRooks;
}

String _makePockets(Pockets pockets) {
  final String wPart = <String>[
    for (final Role r in Role.values)
      ...List<String>.filled(pockets.of(Side.white, r), r.char)
  ].join();
  final String bPart = <String>[
    for (final Role r in Role.values)
      ...List<String>.filled(pockets.of(Side.black, r), r.char)
  ].join();
  return '[${wPart.toUpperCase()}$bPart]';
}

String _makeCastlingFen(Board board, SquareSet unmovedRooks) {
  final StringBuffer buffer = StringBuffer();
  for (final Side color in Side.values) {
    final SquareSet backrank = SquareSet.backrankOf(color);
    final Square? king = board.kingOf(color);
    final SquareSet candidates =
        board.byPiece(Piece(color: color, role: Role.rook)) & backrank;
    for (final Square rook in (unmovedRooks & candidates).squaresReversed) {
      if (rook == candidates.first && king != null && rook < king) {
        buffer.write(color == Side.white ? 'Q' : 'q');
      } else if (rook == candidates.last && king != null && king < rook) {
        buffer.write(color == Side.white ? 'K' : 'k');
      } else {
        final String file = kFileNames[squareFile(rook)];
        buffer.write(color == Side.white ? file.toUpperCase() : file);
      }
    }
  }
  final String fen = buffer.toString();
  return fen != '' ? fen : '-';
}

String _makeRemainingChecks(Tuple2<int, int> checks) =>
    '${checks.item1}+${checks.item2}';

int? _parseSmallUint(String str) =>
    RegExp(r'^\d{1,4}$').hasMatch(str) ? int.parse(str) : null;

int _nthIndexOf(String haystack, String needle, int nth) {
  int index = haystack.indexOf(needle);
  int n = nth;
  while (n-- > 0) {
    if (index == -1) break;
    index = haystack.indexOf(needle, index + needle.length);
  }
  return index;
}

const ByRole<int> _emptyPocket = IMapConst<Role, int>(
  <Role, int>{
    Role.pawn: 0,
    Role.knight: 0,
    Role.bishop: 0,
    Role.rook: 0,
    Role.queen: 0,
    Role.king: 0,
  },
);

const BySide<ByRole<int>> _emptyPocketsBySide =
    IMapConst<Side, IMap<Role, int>>(
  <Side, IMap<Role, int>>{
    Side.white: _emptyPocket,
    Side.black: _emptyPocket,
  },
);