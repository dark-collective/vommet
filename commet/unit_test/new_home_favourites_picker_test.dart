import 'package:commet/client/client.dart';
import 'package:commet/ui/organisms/new_home/new_home_favourites_picker.dart';
import 'package:flutter_test/flutter_test.dart';

class _Room implements Room {
  _Room(this.identifier, {this.isFavorite = false});

  @override
  final String identifier;

  @override
  bool isFavorite;

  @override
  String get localId => "client:$identifier";

  @override
  String get displayName => identifier;

  @override
  Future<void> setAsFavorite(bool favorite) async => isFavorite = favorite;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  test("Vommet issue 793: a DM is a person, other rooms are rooms", () {
    expect(FavouriteCandidate.room(_Room("!dm"), direct: true).kind,
        FavouriteKind.person);
    expect(FavouriteCandidate.room(_Room("!room"), direct: false).kind,
        FavouriteKind.room);
  });

  test("Vommet issue 793: ticking and unticking sets the favorite tag",
      () async {
    final room = _Room("!room");
    final dm = _Room("!dm", isFavorite: true);
    final a = FavouriteCandidate.room(room, direct: false);
    final b = FavouriteCandidate.room(dm, direct: true);
    expect([a.isFavourite, b.isFavourite], [false, true]);

    await a.setFavourite(true);
    await b.setFavourite(false);
    expect([room.isFavorite, dm.isFavorite], [true, false]);
    expect(a.id, "client:!room");
  });
}
