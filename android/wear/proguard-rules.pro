# WorkManager's database (Room 2.5, through work-runtime 2.9) is made by reflection on WorkDatabase_Impl's empty
# constructor, which this R8 removes despite Room's own rules: the release build died at launch on Matt's TAG Heuer
# (2026-10-20, "Failed to create an instance of class androidx.work.impl.WorkDatabase").
-keep class * extends androidx.room.RoomDatabase { <init>(); }
