/// Vommet: whether an `m.room.member` membership means the user is no longer
/// in the room: they left, were kicked or were banned. No member event held
/// (as with lazy-loaded members) counts as still there (Vommet issue 341).
bool matrixMembershipHasLeft(Object? membership) =>
    membership == "leave" || membership == "ban";
