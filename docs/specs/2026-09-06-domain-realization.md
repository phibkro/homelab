# Domain requirements and machine realization

Status: retained design experiment, not a required enforcement architecture.
The subsequent [process model](2026-09-06-process-model.md) establishes the
rewrite's behavioral vocabulary before language or enforcement decisions. This introduces a
candidate checker and a media example; it does not change workload placement,
replace inventory, activate hosts, or translate the model into NixOS or Ansible.

## Two views of the same domain

The core domain is **realizing users' services through authorized, bounded machine
handlers**. The user-oriented view asks who can use a service, for what outcome,
and with which guarantees. The domain-oriented view asks which messages and
effects express that outcome, and which handlers can satisfy their contracts.
These views share identities and requirements; neither is a second inventory.

```text
user principal → client ──request──→ actor identity + mailbox
                                           ↑ authority
                                    service principal

                            actor's service behavior
                                      │ outgoing effects
                                      ▼
                             candidate realization
                                      │
                          machine → handler → resource
                                      │
                            observations and evidence
```

Media, storage, access, compute and availability are provisional semantic areas
for discovering contracts. They are not a prescribed folder taxonomy or proven
bounded contexts. Profiles can select convenient bundles, but satisfaction is
about each service's requirements and its handlers, not a profile name.

## Signature and identity

The proposed signature separates these entities and relations:

| Entity | Meaning and boundary |
|---|---|
| Principal | Identity to which policy grants authority; a person or other accountable subject |
| Client | A caller acting for a principal with an explicit, possibly attenuated authority set |
| Actor | Stable logical identity, incoming mailbox protocol and owned behavior/state; carries authority bounded by its service principal |
| Incarnation | A particular running instance of an actor, with placement and lifetime; restart need not create a new logical actor |
| Service | Behavior offered through an actor and the effect requirements needed to realize it |
| Effect requirement | Requested operation, resource scope, protocol, required laws and resource demand |
| Machine | A location hosting handler implementations and bounded resources |
| Handler | An interpreter of specified effects, with declared protocol/law support and access to a resource |
| Realization | Explicit assignment of every service requirement to a machine handler |
| Evidence | A claim with its artifact, scope and provenance; distinct from the declaration it assesses |

The user principal grants a client permission to invoke a mailbox. A service
principal separately grants the actor authority to perform implementation effects.
A viewer's permission to stream does not grant cache-write or GPU authority to
the viewer, nor does it make the long-lived service actor owned by that viewer.
Request-context propagation and confused-deputy prevention remain runtime
obligations; independent grants alone do not prove that policy.

Mailbox messages are incoming requests; effects are outgoing requests made while
handling them. Their protocols need not coincide. A mailbox address is a logical
reference, not proof that an incarnation is reachable. Authentication and routing
must preserve this distinction at runtime. The executable subset declares actor
identity and mailbox shape; incarnation supervision, delivery and durable state
are not implemented here.

Authority has both an operation and a resource scope. Permission to read one
media collection does not imply permission to read another or to write either.
Authority attenuation is separate from resource accounting: a legitimate caller
can still exceed memory, throughput or concurrency budgets.

## Candidate satisfaction laws

For a declared model `M` and candidate assignment `ρ`, the checker returns a
structured acceptance or rejection. It checks a supplied candidate; it does not
search all placements or optimize costs. The experiment's executable sources
were removed from the active tree during the complete reorganization. They
remain historical evidence at commit `3f4f98cbae8ce4f790ac9d36929bb60e68d8f368`
inside the Git bundle recorded in the
[direct music-ingest acceptance report](../archive/reports/2026-09-06-direct-music-ingest-acceptance.md):

- `domain/realization.nix` — checker
- `domain/examples/media.nix` — media example
- `tests/eval/realization.nix` — counterexamples and acceptance checks

Inspect them without restoring the prototype to the active source tree with
`git show <commit>:<path>` from a clone of that recorded bundle.

The intended static laws are:

1. **References and identity:** references resolve; logical actor identities are
   unique; declarations have the required shapes.
2. **Authority attenuation:** client authority is contained in its principal's
   grants; actor authority is contained in its service principal's grants. Incoming
   requests require an attenuated ingress grant and a compatible mailbox
   protocol/operation. Each outgoing effect uses an authorized operation on its
   declared resource scope.
3. **Total, unambiguous realization:** each service requirement has exactly one
   selected handler. Unknown and extra assignments are rejected.
4. **Protocol and law support:** the selected handler supports the required
   operation and protocol, preserves the logical resource identity, and declares
   the required law names.
5. **Resource fit:** demand is accounted against the selected handler's resource;
   demand and capacity units must match, and aggregate demand must not exceed
   declared capacity. If any allocation requests exclusive access, that machine
   resource can have only one service owner; shared access still has capacity
   limits.
6. **Honest evidence:** static acceptance leaves runtime obligations explicit.
   It must not report live validation or erase an unverified operational claim.

Law-name membership is a declaration check, not a proof that an implementation
obeys an equation. Numeric fit is a calculation over supplied reservations and
capacity, not a measurement of real consumption. The shared/exclusive subset is
not a general treatment of linear, affine or unrestricted resource modalities.
Accounting is local to each declared machine/resource pair. The caller must not
advertise one physical pool as several independent pools; shared remote storage
and cross-machine resource identity need an explicit model before they can be
checked. Bindings place effect handlers, not actor processes. An effect-free
service has no bindings to check and gains no placement or availability guarantee.
The checker reports the precise rejection reasons it implements; this section
states their intended meaning rather than duplicating an error-code table.

Availability belongs in satisfaction alongside authority, protocol and capacity.
A machine that sleeps cannot establish an always-available service merely by
advertising sufficient RAM. This slice leaves availability, failure-domain
independence, live handler behavior and credential enforcement as operational
obligations. It does not accept a deployment as operationally ready.

## Mathematical foundations and their limits

**Algebraic effects** provide a vocabulary of operations and equations;
handlers interpret effectful computations. This motivates separating a service's
effect requirements from the implementation selected to handle them. The Nix
checker compares declared operation/protocol/law support; it does not construct
a free algebra, interpret service programs or prove handler homomorphism laws.
See [Plotkin and Pretnar, Handling Algebraic Effects](https://homepages.inf.ed.ac.uk/gdp/publications/handling-algebraic-effects.pdf).

**Coalgebra and process behavior** address observable evolution: for example a
state space with transitions and observations under incoming messages. Actor
identity, mailbox protocol and incarnation lifecycle belong to that behavioral
account, not solely to an effect signature. This slice does not model traces,
bisimulation, fairness, termination or eventual message delivery. See
[Rutten, Universal coalgebra: a theory of systems](https://ir.cwi.nl/pub/48/).

**Institutions** distinguish signatures, sentences, models and satisfaction,
with truth invariant under suitable changes of notation. For a signature
translation `σ: Σ → Σ′`, their satisfaction condition has the form:

```text
M′ ⊨Σ′ Sen(σ)(φ)  iff  Mod(σ)(M′) ⊨Σ φ
```

This motivates requiring backend translations to preserve requirement meaning.
No NixOS/Ansible translation or full institution is constructed here: signature
morphisms, sentence translation, model reducts and the satisfaction condition
remain design obligations. See [Goguen and Burstall, Institutions](https://publish.lfcs.inf.ed.ac.uk/reports/90/ECS-LFCS-90-106/).

**Category theory** offers composition with explicit interfaces and identity and
associativity laws. Connecting services or handlers is meaningful only when
boundaries compose and shared resource/authority constraints still hold. A graph
of matching labels alone does not establish this. There is no general categorical
composition engine in this slice. See [Fong and Spivak, Seven Sketches in Compositionality](https://ocw.mit.edu/courses/18-s097-applied-category-theory-january-iap-2019/resources/18-s097iap19textbook_pdf/).

**Object capabilities** combine designation and authority, supporting attenuation
through controlled references. The current records model scoped grants; they
are not unforgeable runtime capabilities. Multiplicity and numeric budgets are
additional constraints, not consequences of possessing a capability. See
[Miller, Robust Composition](https://erights.org/talks/thesis/markm-thesis.pdf).

These foundations constrain the design; none licenses calling finite fixture
checks a proof of the whole architecture.

## Executable media slice

From the repository root:

```bash
nix eval --json .#lib.noriRealizationExample
nix build .#checks.x86_64-linux.eval-realization --no-link
```

The first command exposes the example's `model`, proposed `candidate` and checker
`result`. It shows the exact declared inputs alongside acceptance/reasons and
remaining obligations. The second checks the fixture and deliberately invalid
variants. Neither command contacts or activates a machine.

The media example is a semantic fixture, not measured workstation capacity or a
replacement for live media configuration. Read its named operations, resource
units and demands directly from its source. Before expanding the abstraction,
keep the accepted fixture and counterexamples passing and make each new guarantee
explicit about what is checked statically and what requires an observed journey.

A future runtime tracer must additionally decode an external request, perform an
authorized state transition, interpret a real effect, return an observation and
attach artifact provenance. That is distinct from this pure candidate checker.
Any backend integration needs its own translation and live verification contract
before changing the existing Nix and Ansible realizations.
