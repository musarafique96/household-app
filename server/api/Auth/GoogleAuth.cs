namespace Gharbaar.Api.Auth;

// The Web client ID from the Google Cloud project. It is public, so it is config, not a secret.
public sealed record GoogleOptions(string ClientId);

public sealed record GoogleSignInRequest(string? IdToken);
