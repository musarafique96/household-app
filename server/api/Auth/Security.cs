using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace Gharbaar.Api.Auth;

public sealed record JwtOptions(string Key, string Issuer, TimeSpan Lifetime);

public sealed class TokenService(JwtOptions options)
{
    public string Create(Guid userId)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.Key));
        var token = new JwtSecurityToken(
            issuer: options.Issuer,
            audience: options.Issuer,
            claims: new[] { new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()) },
            expires: DateTime.UtcNow.Add(options.Lifetime),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}

// Passwords are stored as "pbkdf2-sha256$iterations$salt$hash" using the built-in .NET PBKDF2.
public sealed class PasswordService
{
    private const int Iterations = 600_000;
    private const int SaltSize = 16;
    private const int KeySize = 32;

    public bool IsStrongEnough(string? password) => !string.IsNullOrEmpty(password) && password.Length >= 8;

    public string Hash(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var key = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, KeySize);
        return $"pbkdf2-sha256${Iterations}${Convert.ToBase64String(salt)}${Convert.ToBase64String(key)}";
    }

    public bool Verify(string stored, string password)
    {
        var parts = stored.Split('$');
        if (parts.Length != 4 || parts[0] != "pbkdf2-sha256" || !int.TryParse(parts[1], out var iterations))
            return false;

        var salt = Convert.FromBase64String(parts[2]);
        var expected = Convert.FromBase64String(parts[3]);
        var actual = Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, expected.Length);
        return CryptographicOperations.FixedTimeEquals(actual, expected);
    }
}
