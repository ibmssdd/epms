EPMS Step 2 UI Starter

Extract the contents of this folder directly into your Flutter project's lib folder.

Expected result:
lib/
  main.dart
  app.dart
  dashboard.dart
  core/
  models/
  screens/
  widgets/

The package intentionally contains no SQLite/database layer yet.

After extraction:
1. Delete/replace the old lib contents only if they are the old experimental files.
2. Keep pubspec.yaml and the normal Flutter project folders.
3. Run:
   flutter analyze
4. Then:
   flutter run

The current dashboard uses in-memory dummy data only. Database integration comes later.
