# Why MongoDB for AI agents

AI agents need three things from a database: a place to retrieve context from,
a place to remember what happened, and a way to do both without moving data
between systems. MongoDB covers all three in one database, so the retrieval
index and the agent's memory live next to the application data instead of in a
separate store that has to be kept in sync.

## Retrieval and memory in one database

MongoDB is both a document database and a vector database. That combination
matters for agents:

- You can search and index vector data alongside your other MongoDB data, so
  embeddings do not need their own database or service.
- You store agent interactions in the same database you already query, in
  collections. The agent reads and writes them with the same connection.
- Documents can embed related data, so an agent can fetch everything it needs
  for a task in a single read instead of joining across services.

The alternative is a vector store for retrieval, a cache for short-term memory,
and a relational database for application state. Each of those is another
system to provision, secure, and keep consistent with the others.

## Why not a relational database

A relational database can store agent data. The question is what shape that data
takes. An agent interaction is nested and varies from step to step: a message
with tool calls, each call with its own arguments and results, retrieved chunks
with scores, and a memory record whose fields grow as you learn what to keep. In
a relational schema that is a set of tables with foreign keys, and each new kind
of tool output is a migration.

MongoDB stores the interaction as one document. The differences that matter:

- **Collections and documents**: A collection holds documents the way a table
  holds rows, and a field plays the role of a column. Unlike a table, documents
  in one collection do not need the same fields, and a field's type can differ
  between documents. A chat turn with three tool calls can sit next to one with
  none.
- **Embedded data over joins**: A document can contain sub-documents and arrays.
  Related data lives in the same record, so the agent reads it in one operation
  instead of joining across tables, and updates it in a single atomic write.
- **Reads follow access patterns**: The modeling principle is that data accessed
  together should be stored together. Fetching a session loads its turns with
  it, not through a chain of joins.
- **Schema grows with the agent**: You can add fields and validation to the
  parts that need it and leave the rest open. A new tool output does not force a
  migration before the agent can store it.

Joins are still available. `$lookup` joins collections, and multi-document
transactions cover cases that span documents. For agent state, modeling the data
so the common reads stay in one document usually removes the need for both.

## What an agent is made of

An agent is a system that completes a task by combining a model with a set of
tools. It gathers context with tools, decides what to do next, and remembers
previous interactions. Four components show up in most designs:

- **Perception**: The input the agent works from. Usually text, sometimes audio,
  images, or other modalities.
- **Planning**: How the agent decides what to do next. This is where the model
  and the prompts live, including reasoning techniques such as chain-of-thought.
- **Tools**: How the agent gathers context and takes action. Tools are functions
  with a name, a description, and parameters. Retrieval is a tool.
- **Memory**: Where past interactions are stored so the agent can use them later.
  Memory is short-term (this session) or long-term (across sessions).

MongoDB covers the tools and the memory.

## Retrieval as a tool

MongoDB exposes several search capabilities that you can wrap as agent tools:

- **Atlas Vector Search**: Retrieves context by semantic meaning. The query and
  the stored text do not need to share keywords.
- **Atlas Search**: Retrieves context by keyword matching and relevance scoring.
- **Hybrid search**: Runs both and combines the results.

Vector search returns results based on meaning rather than exact text. A query
for "red fruit" can return a document about apples even if the document never
uses the phrase "red fruit." That is what makes retrieval useful for questions
phrased in a user's own words.

Hybrid search exists because the two methods fail in different ways. Keyword
search misses paraphrases. Vector search can miss exact identifiers, product
codes, or rare terms. Combining them covers both.

## How hybrid search ranks results

MongoDB runs hybrid search with the `$rankFusion` aggregation stage, available
on MongoDB 8.0 and later. It executes each input pipeline independently, then
de-duplicates and combines the results into one ranked list. MongoDB 8.3 adds
`$scoreFusion`, which combines the scores of the input pipelines instead of
their ranks.

The ranking uses Reciprocal Rank Fusion. For each document in each result set:

1. Take the document's rank `r` and add a constant of 60.
2. Divide 1 by that sum to get the reciprocal rank:

   ```
   reciprocal_rank = 1 / ( r + rank_constant )
   ```

3. Multiply by a per-pipeline weight `w` to control how much that method counts:

   ```
   weighted_reciprocal_rank = w x reciprocal_rank
   ```

4. Sum the weighted ranks for each document across all pipelines.
5. Sort by the combined score.

`$rankFusion` combines the ranked lists, so a document that appears near the top
of one result set still ranks well even if it does not appear in the other.

## Memory as a collection

Because MongoDB stores documents, agent memory is just a collection the agent
reads and writes.

- **Short-term memory** stores the current session: recent conversation turns
  and active task context. A `session_id` field identifies the session, and the
  agent queries for interactions with the same ID to rebuild context.
- **Long-term memory** persists across sessions: user preferences, important
  facts, and past decisions. You can process several interactions with a model to
  extract what is worth keeping, then store it in a separate collection the agent
  queries when needed.

A short-term memory document holds the interaction history for one session:

```json
{
  "session_id": "123",
  "user_id": "jane_doe",
  "interactions": [
    {
      "role": "user",
      "content": "What is MongoDB?",
      "timestamp": "2025-01-01T12:00:00Z"
    },
    {
      "role": "assistant",
      "content": "MongoDB is the world's leading modern database.",
      "timestamp": "2025-01-01T12:00:05Z"
    }
  ]
}
```

A long-term memory document holds what the agent learned about the user:

```json
{
  "user_id": "jane_doe",
  "last_updated": "2025-05-22T09:15:00Z",
  "preferences": {
    "conversation_tone": "casual",
    "custom_instructions": ["I prefer concise answers."]
  },
  "facts": [
    {
      "interests": ["AI", "MongoDB"]
    }
  ]
}
```

You can also index these collections with Atlas Search or Vector Search so the
agent retrieves relevant memories by relevance rather than by scanning a whole
session history.

## Embeddings without a separate pipeline

MongoDB Vector Search can generate embeddings for you with Automated
Embedding, which is in Public Preview. You create a vector search index of type
`autoEmbed`, point it at a text field, and pick a Voyage AI embedding model.
Atlas then embeds that field at index time and embeds your query text at query
time, so the application never calls an embedding API or stores vectors itself.

The models Atlas hosts include `voyage-4-lite` for high-volume, cost-sensitive
work and `voyage-4` for general text search. Because the same model embeds both
the documents and the query, the vectors are always comparable, and Atlas
updates embeddings as the underlying text changes. Token usage is billed per
model, with a one-time free allocation per organization. Atlas stores the
generated embeddings in an internal system collection on the same cluster, so
your application data is not mixed with them.

```python
{
    "fields": [
        {
            "type": "autoEmbed",
            "modality": "text",
            "path": "content",
            "model": "voyage-4-lite",
        },
        {"type": "filter", "path": "file_path"},
    ]
}
```

With that index in place, a query passes plain text. Atlas embeds it and runs
the search:

```javascript
{
    $vectorSearch: {
        index: "autoembed_idx",
        path: "content",
        query: { text: "how do agents remember past sessions" },
        numCandidates: 100,
        limit: 5,
    }
}
```

If you manage embeddings yourself, Atlas still stores the vectors in the same
document as the text they came from, so there is no second copy to reconcile.

## Access from agent frameworks

MongoDB integrates with the frameworks agents are commonly built in, so you do
not have to write the connection layer yourself:

- **LangChain** provides `MongoDBChatMessageHistory` for message history and
  `MongoDBAtlasSemanticCache` for caching model responses.
- **LangGraph** provides `MongoDBSaver` for short-term checkpointing and
  `MongoDBStore` for long-term memory.
- **MCP** exposes MongoDB to AI clients through the Model Context Protocol, so a
  host such as an IDE or chat client can query data with a standard tool
  interface.

## The short version

Agents need retrieval and memory. Most stacks split those across a vector store,
a cache, and an application database, then spend effort keeping them consistent.
A relational database can hold the same data, but an agent's state is nested and
changes shape as you add tools, which means migrations and joins to read it back.
MongoDB stores retrieval and memory in the same collections the agent already
reads and writes, with `$rankFusion` for hybrid retrieval. One database, one
connection, one thing to operate.
