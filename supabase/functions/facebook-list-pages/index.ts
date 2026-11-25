// Point d'entrée : toute la logique est dans handler.ts (testable sans serveur).
import { handle } from "./handler.ts";

Deno.serve(handle);
