/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations.dart';
import 'package:luma/database.dart';
import 'package:luma/models/category.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v1.dart' as v1;
import 'generated_migrations/schema_v2.dart' as v2;
import 'generated_migrations/schema_v3.dart' as v3;
import 'generated_migrations/schema_v4.dart' as v4;
import 'generated_migrations/schema_v5.dart' as v5;
import 'generated_migrations/schema_v10.dart' as v10;

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test("upgrade from v1 to current schema", () async {
    final schema = await verifier.schemaAt(1);

    final oldDb = v1.DatabaseAtV1(schema.newConnection().executor);
    await oldDb
        .into(oldDb.apps)
        .insert(
          v1.AppsCompanion.insert(
            packageName: "app.luma.tvlauncher",
            name: "Luma",
            className: ".MainActivity",
            version: "0.0.1",
          ),
        );
    final categoryId = await oldDb
        .into(oldDb.categories)
        .insert(v1.CategoriesCompanion.insert(name: "Applications", order: 0));
    await oldDb
        .into(oldDb.appsCategories)
        .insert(
          v1.AppsCategoriesCompanion.insert(
            categoryId: categoryId,
            appPackageName: "app.luma.tvlauncher",
            order: 0,
          ),
        );
    await oldDb.close();

    final db = LumaDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, db.schemaVersion);
    await db.close();

    final migratedDb = LumaDatabase(schema.newConnection());
    final app = await migratedDb.select(migratedDb.apps).getSingle();
    final category = await migratedDb.select(migratedDb.categories).getSingle();
    final appsCategory = await migratedDb
        .select(migratedDb.appsCategories)
        .getSingle();
    expect(app.packageName, "app.luma.tvlauncher");
    expect(app.name, "Luma");
    expect(app.version, "0.0.1");
    expect(app.hidden, false);
    expect(app.sideloaded, false);
    expect(category.id, 1);
    expect(category.name, "Applications");
    expect(category.order, 0);
    expect(category.sort, CategorySort.manual);
    expect(category.type, CategoryType.grid);
    expect(category.columnsCount, 6);
    expect(category.rowHeight, 110);
    expect(appsCategory.appPackageName, "app.luma.tvlauncher");
    expect(appsCategory.categoryId, 1);
    expect(appsCategory.order, 0);
    await migratedDb.close();
  });

  test("upgrade from v2 to current schema", () async {
    final schema = await verifier.schemaAt(2);

    final oldDb = v2.DatabaseAtV2(schema.newConnection().executor);
    await oldDb
        .into(oldDb.apps)
        .insert(
          v2.AppsCompanion.insert(
            packageName: "app.luma.tvlauncher",
            name: "Luma",
            version: "0.0.1",
          ),
        );
    final categoryId = await oldDb
        .into(oldDb.categories)
        .insert(v2.CategoriesCompanion.insert(name: "Applications", order: 0));
    await oldDb
        .into(oldDb.appsCategories)
        .insert(
          v2.AppsCategoriesCompanion.insert(
            categoryId: categoryId,
            appPackageName: "app.luma.tvlauncher",
            order: 0,
          ),
        );
    await oldDb.close();

    final db = LumaDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, db.schemaVersion);
    await db.close();

    final migratedDb = LumaDatabase(schema.newConnection());
    final app = await migratedDb.select(migratedDb.apps).getSingle();
    final category = await migratedDb.select(migratedDb.categories).getSingle();
    final appsCategory = await migratedDb
        .select(migratedDb.appsCategories)
        .getSingle();
    expect(app.packageName, "app.luma.tvlauncher");
    expect(app.name, "Luma");
    expect(app.version, "0.0.1");
    expect(app.hidden, false);
    expect(app.sideloaded, false);
    expect(category.id, 1);
    expect(category.name, "Applications");
    expect(category.order, 0);
    expect(category.sort, CategorySort.manual);
    expect(category.type, CategoryType.grid);
    expect(category.columnsCount, 6);
    expect(category.rowHeight, 110);
    expect(appsCategory.appPackageName, "app.luma.tvlauncher");
    expect(appsCategory.categoryId, 1);
    expect(appsCategory.order, 0);
    await migratedDb.close();
  });

  test("upgrade from v3 to current schema", () async {
    final schema = await verifier.schemaAt(3);

    final oldDb = v3.DatabaseAtV3(schema.newConnection().executor);
    await oldDb
        .into(oldDb.apps)
        .insert(
          v3.AppsCompanion.insert(
            packageName: "app.luma.tvlauncher",
            name: "Luma",
            version: "0.0.1",
          ),
        );
    final categoryId = await oldDb
        .into(oldDb.categories)
        .insert(v3.CategoriesCompanion.insert(name: "Applications", order: 0));
    await oldDb
        .into(oldDb.appsCategories)
        .insert(
          v3.AppsCategoriesCompanion.insert(
            categoryId: categoryId,
            appPackageName: "app.luma.tvlauncher",
            order: 0,
          ),
        );
    await oldDb.close();

    final db = LumaDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, db.schemaVersion);
    await db.close();

    final migratedDb = LumaDatabase(schema.newConnection());
    final app = await migratedDb.select(migratedDb.apps).getSingle();
    final category = await migratedDb.select(migratedDb.categories).getSingle();
    final appsCategory = await migratedDb
        .select(migratedDb.appsCategories)
        .getSingle();
    expect(app.packageName, "app.luma.tvlauncher");
    expect(app.name, "Luma");
    expect(app.version, "0.0.1");
    expect(app.hidden, false);
    expect(app.sideloaded, false);
    expect(category.id, 1);
    expect(category.name, "Applications");
    expect(category.order, 0);
    expect(category.sort, CategorySort.manual);
    expect(category.type, CategoryType.grid);
    expect(category.columnsCount, 6);
    expect(category.rowHeight, 110);
    expect(appsCategory.appPackageName, "app.luma.tvlauncher");
    expect(appsCategory.categoryId, 1);
    expect(appsCategory.order, 0);
    await migratedDb.close();
  });

  test("upgrade from v4 to current schema", () async {
    final schema = await verifier.schemaAt(4);

    final oldDb = v4.DatabaseAtV4(schema.newConnection().executor);
    await oldDb
        .into(oldDb.apps)
        .insert(
          v4.AppsCompanion.insert(
            packageName: "app.luma.tvlauncher",
            name: "Luma",
            version: "0.0.1",
          ),
        );
    final categoryId = await oldDb
        .into(oldDb.categories)
        .insert(
          v4.CategoriesCompanion.insert(
            name: "Applications",
            type: Value(1),
            order: 0,
          ),
        );
    await oldDb
        .into(oldDb.appsCategories)
        .insert(
          v4.AppsCategoriesCompanion.insert(
            categoryId: categoryId,
            appPackageName: "app.luma.tvlauncher",
            order: 0,
          ),
        );
    await oldDb.close();

    final db = LumaDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, db.schemaVersion);
    await db.close();

    final migratedDb = LumaDatabase(schema.newConnection());
    final app = await migratedDb.select(migratedDb.apps).getSingle();
    final category = await migratedDb.select(migratedDb.categories).getSingle();
    final appsCategory = await migratedDb
        .select(migratedDb.appsCategories)
        .getSingle();
    expect(app.packageName, "app.luma.tvlauncher");
    expect(app.name, "Luma");
    expect(app.version, "0.0.1");
    expect(app.hidden, false);
    expect(app.sideloaded, false);
    expect(category.id, 1);
    expect(category.name, "Applications");
    expect(category.order, 0);
    expect(category.sort, CategorySort.manual);
    expect(category.type, CategoryType.grid);
    expect(category.columnsCount, 6);
    expect(category.rowHeight, 110);
    expect(appsCategory.appPackageName, "app.luma.tvlauncher");
    expect(appsCategory.categoryId, 1);
    expect(appsCategory.order, 0);
    await migratedDb.close();
  });
  test(
    'upgrade from v5 preserves hidden apps and category membership',
    () async {
      final schema = await verifier.schemaAt(5);
      final oldDb = v5.DatabaseAtV5(schema.newConnection().executor);
      await oldDb
          .into(oldDb.apps)
          .insert(
            v5.AppsCompanion.insert(
              packageName: 'hidden.app',
              name: 'Hidden app',
              version: '1',
              hidden: const Value(true),
            ),
          );
      final categoryId = await oldDb
          .into(oldDb.categories)
          .insert(
            v5.CategoriesCompanion.insert(
              name: 'Personal collection',
              order: 0,
            ),
          );
      await oldDb
          .into(oldDb.appsCategories)
          .insert(
            v5.AppsCategoriesCompanion.insert(
              categoryId: categoryId,
              appPackageName: 'hidden.app',
              order: 3,
            ),
          );
      await oldDb.close();
      final db = LumaDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, db.schemaVersion);
      expect((await db.getApplications()).single.hidden, true);
      expect((await db.getAppsCategories()).single.order, 3);
      expect((await db.getApplications()).single.lastLaunchedAt, isNull);
      await db.close();
    },
  );
  test(
    'upgrade from deployed schema 10 preserves recent history and favourites',
    () async {
      final schema = await verifier.schemaAt(10);
      final oldDb = v10.DatabaseAtV10(schema.newConnection().executor);
      final launchedAt = DateTime(2026, 11, 5, 20);
      await oldDb
          .into(oldDb.apps)
          .insert(
            v10.AppsCompanion.insert(
              packageName: 'tv.app',
              name: 'TV app',
              version: '1',
              lastLaunchedAt: Value(launchedAt),
            ),
          );
      final id = await oldDb
          .into(oldDb.categories)
          .insert(v10.CategoriesCompanion.insert(name: 'Favorites', order: 0));
      await oldDb
          .into(oldDb.appsCategories)
          .insert(
            v10.AppsCategoriesCompanion.insert(
              categoryId: id,
              appPackageName: 'tv.app',
              order: 2,
            ),
          );
      await oldDb.close();
      final db = LumaDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, db.schemaVersion);
      expect((await db.getApplications()).single.lastLaunchedAt, launchedAt);
      expect((await db.getCategories()).single.type, CategoryType.row);
      expect((await db.getAppsCategories()).single.order, 2);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      await db.close();
    },
  );
}
