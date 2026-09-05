import 'board_state.dart';
import 'light_element.dart';

abstract interface class BoardCommand {
  BoardState apply(BoardState state);
  BoardState revert(BoardState state);
}

class AddElementCommand implements BoardCommand {
  const AddElementCommand(this.element);

  final LightElement element;

  @override
  BoardState apply(BoardState state) => state.add(element);

  @override
  BoardState revert(BoardState state) => state.remove(element.id);
}

class RemoveElementCommand implements BoardCommand {
  const RemoveElementCommand(this.element);

  final LightElement element;

  @override
  BoardState apply(BoardState state) => state.remove(element.id);

  @override
  BoardState revert(BoardState state) => state.add(element);
}

class ReplaceElementCommand implements BoardCommand {
  const ReplaceElementCommand({required this.before, required this.after});

  final LightElement before;
  final LightElement after;

  @override
  BoardState apply(BoardState state) => state.replace(after);

  @override
  BoardState revert(BoardState state) => state.replace(before);
}
