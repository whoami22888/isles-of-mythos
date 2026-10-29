// Durable, append-only anti-cheat evidence. Detection windows live in Redis; this table preserves the
// security-relevant decisions across restarts and across backend instances.
//
// Integrity: rows cannot be updated, and can only be deleted by the retention routine, which declares
// itself with SET LOCAL isles.anti_cheat_retention = 'on'. This guards against application bugs and
// injected single statements; it is not a substitute for restricting database roles in deployment.
export const up = (pgm) => {
  pgm.createTable("anti_cheat_evidence", {
    id: { type: "bigserial", primaryKey: true },
    user_id: { type: "uuid", notNull: true },
    event_type: { type: "text", notNull: true },
    severity: { type: "text", notNull: true },
    suspicion: { type: "numeric(6,2)", notNull: true },
    suppressed_count: { type: "integer", notNull: true, default: 0 },
    evidence: { type: "jsonb", notNull: true, default: pgm.func("'{}'::jsonb") },
    occurred_at: { type: "timestamptz", notNull: true },
    recorded_at: { type: "timestamptz", notNull: true, default: pgm.func("now()") },
  });
  pgm.addConstraint("anti_cheat_evidence", "anti_cheat_evidence_severity_check", {
    check: "severity IN ('LOW','MEDIUM','HIGH','CRITICAL')",
  });
  pgm.addConstraint("anti_cheat_evidence", "anti_cheat_evidence_suspicion_check", {
    check: "suspicion >= 0 AND suspicion <= 100",
  });
  pgm.addConstraint("anti_cheat_evidence", "anti_cheat_evidence_size_check", {
    check: "octet_length(evidence::text) <= 4096",
  });
  pgm.createIndex("anti_cheat_evidence", ["user_id", { name: "occurred_at", sort: "DESC" }], {
    name: "anti_cheat_evidence_user_occurred_idx",
  });
  pgm.createIndex("anti_cheat_evidence", "occurred_at", { name: "anti_cheat_evidence_occurred_idx" });

  pgm.createFunction(
    "anti_cheat_evidence_guard",
    [],
    { returns: "trigger", language: "plpgsql", replace: true },
    `
    BEGIN
      IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'anti_cheat_evidence is append-only';
      END IF;
      IF TG_OP = 'DELETE' AND coalesce(current_setting('isles.anti_cheat_retention', true), '') <> 'on' THEN
        RAISE EXCEPTION 'anti_cheat_evidence rows may only be removed by the retention routine';
      END IF;
      IF TG_OP = 'DELETE' THEN
        RETURN OLD;
      END IF;
      RETURN NEW;
    END;
    `,
  );
  pgm.createTrigger("anti_cheat_evidence", "anti_cheat_evidence_guard_trigger", {
    when: "BEFORE",
    operation: ["UPDATE", "DELETE"],
    level: "ROW",
    function: "anti_cheat_evidence_guard",
  });
};

export const down = (pgm) => {
  pgm.dropTrigger("anti_cheat_evidence", "anti_cheat_evidence_guard_trigger", { ifExists: true });
  pgm.dropFunction("anti_cheat_evidence_guard", [], { ifExists: true });
  pgm.dropTable("anti_cheat_evidence");
};
