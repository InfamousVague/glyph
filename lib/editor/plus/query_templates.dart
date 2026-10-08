/// The databases the + offers ready-made, and a query's fence as the + writes one. These were ported here ahead of
/// the queries themselves; they live in lib/core/query now (templates.dart, a port of
/// `src/app/core/query/templates.ts`, and fence.dart's `queryFence`, of `core/query/fence.ts`), and this file hands
/// them on so the + list reads as it did.
library;

export '../../core/query/fence.dart' show queryFence;
export '../../core/query/templates.dart' show QueryTemplate, queryTemplates;
