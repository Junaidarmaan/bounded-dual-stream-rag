# Bounded Dual-Stream RAG & Ingestion Firewall

A small RAG system built with n8n, PostgreSQL, pgvector, and Gemini.

The project processes meeting transcripts, identifies relevant coaching sessions, and stores their knowledge in two separate streams:

- **Framework:** Structured coaching knowledge, concepts, and actionable takeaways.
- **Voice Sample:** Verbatim dialogue from the coach, used to guide the response style.

When a user asks a question, the system retrieves relevant coaching knowledge and generates an answer grounded in the stored information.

## Tech Stack

- n8n for workflow automation
- Docker Compose for local setup
- PostgreSQL 16 for data storage
- pgvector for vector similarity search
- Gemini for meeting classification, extraction, embeddings, and response generation

## Project Structure

```text
.
├── docker-compose.yml
├── init.sql
├── README.md
├── data/
│   └── mock_transcripts.json
└── workflows/
    ├── ingestion_firewall.json
    └── gated_retrieval.json
```

## Getting Started

### 1. Start the containers

Make sure Docker and Docker Compose are installed.

Run:

```bash
docker compose up -d
```

This starts n8n and PostgreSQL.

### 2. Open n8n

Visit:

```text
http://localhost:5678
```

Complete the initial n8n setup if required.

### 3. Import the workflows

Import both JSON files from the `workflows` directory:

- `ingestion_firewall.json`
- `gated_retrieval.json`

### 4. Configure Gemini API access

Configure your Gemini API credentials in the relevant HTTP Request nodes.

Do not commit API keys or other secrets to the repository.

### 5. Run the ingestion workflow

The input dataset is available at:

```text
data/mock_transcripts.json
```

The ingestion workflow reads the transcripts, classifies the meetings, and stores accepted or rejected sessions in PostgreSQL.

## How It Works

### Workflow A: Ingestion & Semantic Firewall

The first workflow processes the meeting transcripts.

**1. Bounded transcript sampling**

To avoid sending unnecessarily large transcripts to the classifier:

- Transcripts containing 60 or fewer turns are processed completely.
- Longer transcripts are sampled using the first 40 and last 20 turns.

**2. Meeting classification**

Gemini classifies each meeting into one of the following categories:

- Client Coaching
- Internal Operations
- Sales Discovery
- Other

It also returns a confidence score and a short summary.

**3. Ingestion firewall**

A meeting is accepted only when:

```text
meeting_type = Client Coaching
confidence_score >= 0.80
```

Rejected meetings are stored in the `rejected_meetings` table. They are not embedded or added to the knowledge base.

**4. Dual-stream extraction**

Accepted meetings are processed into two streams:

- Frameworks contain structured coaching knowledge and practical takeaways.
- Voice samples contain only the coach's original dialogue, without paraphrasing.

Voice samples are split into chunks of approximately 400–700 characters.

**5. Embedding and storage**

Both streams are converted into 1536-dimensional embeddings using Gemini and stored in the `knowledge_vault` table.

### Workflow B: Gated Retrieval & Persona Synthesis

The second workflow handles user questions.

**1. Greeting detection**

Simple greetings such as `Hi` and `Hello` receive a static response without calling the embedding API or querying the database.

**2. Query embedding**

Other messages are converted into embeddings using Gemini.

**3. Framework retrieval**

The system searches for relevant framework records using cosine similarity.

- Minimum similarity: `0.70`
- Maximum results: `2`

**4. Zero-match circuit breaker**

If no framework matches the required threshold, the workflow returns:

```text
No documented coaching frameworks match this topic.
```

The response generation LLM is not called in this case.

**5. Voice retrieval**

When relevant frameworks are found, the system also retrieves voice samples.

- Minimum similarity: `0.65`
- Maximum results: `2`

**6. Response generation**

The retrieved frameworks provide the knowledge for the answer. Voice samples guide the communication style.

Gemini generates a clear, practical response grounded in the retrieved context.

## Database Design

### `knowledge_vault`

Stores accepted coaching knowledge and voice samples.

| Column | Description |
|---|---|
| id | Unique record ID |
| session_id | Original meeting ID |
| stream_type | framework or voice_sample |
| content | Stored text |
| metadata | Additional JSON information |
| embedding | 1536-dimensional vector |
| created_at | Record creation time |

An HNSW index using cosine distance is created on the embedding column to support vector similarity searches.

### `rejected_meetings`

Stores meetings rejected by the ingestion firewall.

It contains the meeting ID, title, classification, confidence score, summary, rejection reason, and metadata.

Rejected meetings are stored as ordinary relational records, without embeddings.

## Verification

The workflows were tested using the supplied mock dataset.

| Meeting ID | Meeting | Expected Result |
|---|---|---|
| SES-101 | Weekly Strategy Session | Accepted |
| SES-102 | Executive Catch-up | Accepted |
| SES-103 | Technical Sync & Integrations | Rejected |
| SES-104 | Partnership Discovery Call | Rejected |

Database verification:

- 2 framework records inserted.
- 4 voice sample records inserted.
- 2 rejected meetings archived.
- All stored embeddings have 1536 dimensions.

Retrieval verification:

- Greetings return a static response without database retrieval.
- Relevant coaching questions retrieve framework and voice context.
- Questions outside the coaching knowledge base return the fallback response without calling the generation LLM.

## Design Decisions

### Why use SQL threshold gating instead of asking the LLM to say "I don't know"?

The system checks similarity thresholds before calling the response generation model.

This provides a deterministic way to reject queries that do not have sufficiently relevant stored knowledge. It also avoids unnecessary LLM calls and reduces the chance of generating unsupported answers.

An LLM instruction alone cannot guarantee that irrelevant context will be rejected.

### Why use HNSW and how does `ef_search` affect retrieval?

HNSW is an approximate nearest-neighbor index used for efficient vector searches.

The `ef_search` parameter controls how many candidates are explored during a search.

- A higher value generally improves recall but requires more search work and can increase query latency.
- A lower value generally improves speed but may miss relevant results.

The right value depends on the balance between retrieval quality and performance.

## Notes

This project is a local assessment implementation using a small mock dataset. Similarity thresholds and retrieval settings may need further tuning when working with larger datasets.

