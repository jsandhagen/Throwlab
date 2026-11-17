import '../models/training_note.dart';

/// Where the note editor saves to. Training notes and notebook pages are
/// stored apart — they are about different things — but the editor that
/// writes them is one screen, and this is all it needs of either store.
abstract class NoteStore {
  /// Writes [document] back, inserting it if it is new.
  Future<void> saveDocument(NoteDocument document);

  Future<void> remove(String id);

  /// Copies a picked picture into the app's own storage, and hands back the
  /// path to keep on the block.
  Future<String?> adoptPicture(
      String documentId, String blockId, String sourcePath);

  /// Reclaims one deleted block's picture.
  Future<void> deletePicture(String path);
}
