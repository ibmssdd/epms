import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._privateConstructor();

  static final AppDatabase instance = AppDatabase._privateConstructor();

  static Database? _database;
  static Future<Database>? _openingDatabase;

  // --------------------------------------------------------------------------
  // DATABASE VERSION
  // --------------------------------------------------------------------------

  static const int _databaseVersion = 2;

  // --------------------------------------------------------------------------
  // DATABASE ACCESS
  // --------------------------------------------------------------------------

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    if (_openingDatabase != null) {
      return _openingDatabase!;
    }

    _openingDatabase = _openDatabase();

    try {
      _database = await _openingDatabase!;
      return _database!;
    } finally {
      _openingDatabase = null;
    }
  }

  // --------------------------------------------------------------------------
  // OPEN DATABASE
  // --------------------------------------------------------------------------

  Future<Database> _openDatabase() async {
    final databaseDirectory = await getDatabasesPath();

    final databasePath = join(databaseDirectory, 'epms.db');

    final databaseFile = File(databasePath);

    // ------------------------------------------------------------------------
    // FIRST INSTALL
    // ------------------------------------------------------------------------

    if (!await databaseFile.exists()) {
      await _copyBaselineDatabase(databasePath);
    }

    // ------------------------------------------------------------------------
    // OPEN / MIGRATE DATABASE
    // ------------------------------------------------------------------------

    return openDatabase(
      databasePath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createTaskActivityStatusTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTaskActivityStatusTable(db);
        }
      },
    );
  }

  // --------------------------------------------------------------------------
  // TASK ACTIVITY STATUS TABLE
  // --------------------------------------------------------------------------

  static Future<void> _createTaskActivityStatusTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS "db_TaskActivityStatus" (
        "TaskID" TEXT NOT NULL,
        "ActivityStatusJSON" TEXT NOT NULL DEFAULT '{}',
        "TaskActivityUpdatedDate" TEXT,
        PRIMARY KEY("TaskID"),
        CHECK(length(trim("TaskID")) > 0),
        CHECK(length(trim("ActivityStatusJSON")) > 0)
      );
      ''');
  }

  // --------------------------------------------------------------------------
  // COPY BASELINE DATABASE
  // --------------------------------------------------------------------------

  Future<void> _copyBaselineDatabase(String databasePath) async {
    final databaseDirectory = dirname(databasePath);

    await Directory(databaseDirectory).create(recursive: true);

    final baselineBytes = await rootBundle.load('assets/database/epms.db');

    final bytes = baselineBytes.buffer.asUint8List(
      baselineBytes.offsetInBytes,
      baselineBytes.lengthInBytes,
    );

    final databaseFile = File(databasePath);

    await databaseFile.writeAsBytes(bytes, flush: true);
  }

  // --------------------------------------------------------------------------
  // CLOSE DATABASE
  // --------------------------------------------------------------------------

  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
