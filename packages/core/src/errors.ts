/** Erreur métier avec un message lisible (français) et un code stable. */
export class DomainError extends Error {
  constructor(
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "DomainError";
  }
}

export class InvalidTransitionError extends DomainError {
  constructor(
    public readonly from: string,
    public readonly event: string,
    public readonly to: string,
  ) {
    super("invalid_transition", `Transition interdite : ${from} --(${event})--> ${to}`);
    this.name = "InvalidTransitionError";
  }
}

/** Opération non supportée par un prestataire : jamais simulée. */
export class UnsupportedOperationError extends Error {
  constructor(provider: string, operation: string) {
    super(`Le prestataire ${provider} ne supporte pas l'opération « ${operation} »`);
    this.name = "UnsupportedOperationError";
  }
}

export class InvalidSignatureError extends Error {
  constructor(message = "Signature de webhook invalide") {
    super(message);
    this.name = "InvalidSignatureError";
  }
}

/** Erreur d'appel à un service externe. `transient` = à réessayer plus tard. */
export class ExternalServiceError extends Error {
  constructor(
    public readonly service: string,
    message: string,
    public readonly transient: boolean,
    public readonly status?: number,
  ) {
    super(`${service} : ${message}`);
    this.name = "ExternalServiceError";
  }
}
