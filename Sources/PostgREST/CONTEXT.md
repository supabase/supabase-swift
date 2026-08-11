# PostgREST

Reads and writes data that a Postgres database exposes over PostgREST. This context owns
the vocabulary for describing where rows come from, how they are narrowed, and what a
failed call means.

## Language

### Data sources

**Relation**:
A queryable source of rows in the database — a table, a view, or a materialized view.
_Avoid_: entity, model, table (when views are also meant)

**Writable Relation**:
A relation the database accepts writes for. Tables, plus views Postgres reports as
updatable.
_Avoid_: mutable relation, editable table

**Row**:
A single record belonging to a relation.
_Avoid_: record, item, object

**Selection**:
A named subset of a relation's columns, possibly including embedded resources. A selection
selects from a relation; it is never itself a relation.
_Avoid_: projection, DTO, select shape, view, partial

**Relationship**:
A named link between two relations, identified by the foreign key column that defines it. The
foreign key is a column; the relationship is the link that column establishes.
_Avoid_: join, foreign key (that is the column), association

**Embedded Resource**:
Rows of a related relation returned nested inside a parent relation's rows. PostgREST's own
term, and it applies to the filters, ordering and limits scoped to that nested relation.
_Avoid_: join, include, referenced table, nested table

**Required Embed**:
An embedded resource that also constrains its parent, so parent rows with no matching
embedded row are dropped. Distinct from a plain embedded resource, where filtering narrows
only the nested rows and every parent is still returned.
_Avoid_: inner join, mandatory embed

**Database Function**:
A Postgres function invoked by name with arguments, producing rows. A function is not a
relation — it produces one — so it cannot be used where a relation is expected.
_Avoid_: stored procedure (Postgres distinguishes the two), RPC (that is the act of calling
one, not the thing itself)

### Requests

**Source**:
A relation that has been chosen but for which no operation has been picked yet.
_Avoid_: builder, table, from

**Query**:
A request that reads rows.
_Avoid_: select, fetch, statement

**Mutation**:
A request that writes rows — insert, upsert, update or delete.
_Avoid_: write, command, statement

**Filter**:
A predicate over a relation's columns, composed from other filters. A filter is a value
independent of any request, so the same one can be reused across many.
_Avoid_: condition, where clause, predicate, constraint

### Errors

**Server Error**:
The error body PostgREST returns in a failed response — its code, message, hint and details.
A description of what the server rejected.
_Avoid_: Postgres error, API error

**Request Error**:
The failure a call raises. It distinguishes a rejection by the server from a failure to
reach it and from a failure to decode its reply, and it carries the server error when there
was one.
_Avoid_: client error, query error
