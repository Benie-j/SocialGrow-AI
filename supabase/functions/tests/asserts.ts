// Assertions minimales, sans dépendance externe.

export function assert(condition: unknown, message = "Assertion fausse"): asserts condition {
  if (!condition) throw new Error(message);
}

// Comparaison profonde ; l'ordre des clés d'objet est ignoré.
function normalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(normalize);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => [k, normalize(v)]),
    );
  }
  return value;
}

export function assertEquals(actual: unknown, expected: unknown, message?: string): void {
  const a = JSON.stringify(normalize(actual));
  const e = JSON.stringify(normalize(expected));
  if (a !== e) throw new Error(message ?? `Attendu ${e}, obtenu ${a}`);
}

export function assertNotEquals(actual: unknown, unexpected: unknown, message?: string): void {
  if (JSON.stringify(normalize(actual)) === JSON.stringify(normalize(unexpected))) {
    throw new Error(message ?? `Valeur inattendue : ${JSON.stringify(actual)}`);
  }
}

export function assertStringIncludes(actual: string, expected: string): void {
  if (!actual.includes(expected)) throw new Error(`« ${actual} » ne contient pas « ${expected} »`);
}
