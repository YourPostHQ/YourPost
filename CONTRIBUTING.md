# Contributing to YourPost

Thank you for your interest in contributing to YourPost! This document provides guidelines for contributing to the project.

## 🚀 Getting Started

### Repository Structure

- **GitHub**: [github.com/yourpost/yourpost](https://github.com/yourpost/yourpost)
- **Documentation**: [yourpost.io](https://yourpost.io)
- **Live Demo**: [yourpost.app](https://yourpost.app)
- **Organization**: [Devstroop Technologies](https://devstroop.com)

### Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md) to ensure a welcoming environment for everyone.

## 📋 How to Contribute

### Reporting Bugs

1. **Search existing issues** - Check if the bug is already reported
2. **Create a new issue** - Use the bug report template
3. **Include details**:
   - YourPost version
   - Operating system
   - Steps to reproduce
   - Expected vs actual behavior
   - Logs (if applicable)

### Suggesting Features

1. **Check existing issues** - See if it's already requested
2. **Create a feature request** - Use the feature request template
3. **Describe the use case** - Why is this feature needed?
4. **Propose a solution** - How should it work?

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes**
4. **Test your changes**
5. **Commit**: `git commit -m 'Add amazing feature'`
6. **Push**: `git push origin feature/amazing-feature`
7. **Open a Pull Request**

## 🛠️ Development Setup

### Prerequisites

- Zig 0.16.0 or later
- SQLite3 development libraries
- OpenSSL (optional, for TLS)

### Building

```bash
# Clone the repository
git clone https://github.com/yourpost/yourpost.git
cd yourpost

# Build
zig build -Doptimize=ReleaseFast

# Run
./zig-out/bin/yourpost
```

### Testing

```bash
# Run in development mode
YP_SMTP_PORT=2525 YP_API_PORT=9000 ./zig-out/bin/yourpost

# Test API
curl http://localhost:9000/health
```

## 📝 Code Style

### Zig Code

- Follow Zig's official style guide
- Use `std.log` for logging
- Handle errors properly (no `catch unreachable` in production code)
- Document public functions
- Use meaningful variable names

### Example

```zig
/// Handles incoming SMTP connections
/// Thread-safe and handles errors gracefully
fn handleConnection(stream: std.Io.net.Stream) !void {
    const reader = stream.reader();
    const writer = stream.writer();
    
    // Send greeting
    try writer.writeAll("220 mail.example.com ESMTP YourPost\r\n");
    
    // Handle commands
    while (true) {
        const line = reader.readUntilDelimiterAlloc(allocator, '\n', 4096) catch |err| {
            std.log.warn("Read error: {}", .{err});
            break;
        };
        defer allocator.free(line);
        
        // Process command
        try processCommand(line, writer);
    }
}
```

### Documentation

- Update relevant docs when changing features
- Use clear, concise language
- Include examples
- Follow Markdown best practices

## 🔧 Areas for Contribution

### Code Contributions

- **Core Features**: SMTP, POP3, IMAP improvements
- **Security**: TLS, authentication, encryption
- **Performance**: Optimization, connection handling
- **API**: New endpoints, improvements
- **Storage**: Database optimizations

### Documentation

- **User Guide**: Tutorials, how-tos
- **API Docs**: Endpoint documentation
- **Examples**: Code samples, use cases
- **Translations**: Multi-language docs

### Testing

- **Unit Tests**: Core functionality
- **Integration Tests**: End-to-end scenarios
- **Performance Tests**: Load testing
- **Security Tests**: Vulnerability testing

### Community

- **Bug Reports**: Testing and reporting
- **Answering Questions**: Forums, discussions
- **Translations**: Interface, documentation
- **Tutorials**: Blog posts, videos

## 🧪 Testing Guidelines

### Unit Tests

```zig
const std = @import("std");
const testing = std.testing;

test "basic addition" {
    try testing.expect(1 + 1 == 2);
}
```

Run tests:

```bash
zig build test
```

### Integration Tests

```bash
# Start server
YP_SMTP_PORT=2525 ./zig-out/bin/yourpost &

# Run tests
./test/integration.sh

# Stop server
kill %1
```

## 🔒 Security Considerations

### Reporting Vulnerabilities

**Do not create public GitHub issues for security vulnerabilities!**

Instead:

1. Email: security@yourpost.io
2. Include detailed description
3. Provide reproduction steps
4. Suggest fixes (if possible)

We'll respond within 48 hours.

### Secure Coding

- Validate all input
- Use parameterized queries
- Handle errors gracefully
- Don't log sensitive data
- Use constant-time comparisons for secrets

## 📦 Release Process

### Version Numbers

We follow [Semantic Versioning](https://semver.org/):

- `MAJOR.MINOR.PATCH`
- Breaking changes → MAJOR bump
- New features → MINOR bump
- Bug fixes → PATCH bump

### Creating a Release

1. Update `CHANGELOG.md`
2. Update version in code
3. Create git tag: `git tag v1.2.3`
4. Push tag: `git push origin v1.2.3`
5. Create GitHub Release
6. Update documentation
7. Announce on website

## 🤝 Community

### Communication Channels

- **GitHub Discussions**: General questions, ideas
- **Discord**: [discord.devstroop.com](https://discord.devstroop.com)
- **Forum**: [forum.yourpost.io](https://forum.yourpost.io)
- **Email**: hello@yourpost.io

### Events

- Monthly community calls
- Quarterly contributor meetings
- Annual conference (YourPostCon)

## 🏆 Recognition

Contributors receive:

- Listed in CONTRIBUTORS.md
- Contributor badge on GitHub
- Swag (stickers, t-shirts)
- Recognition on website
- Invite to private community

## 📄 License

By contributing, you agree that your contributions will be licensed under the AGPLv3.

## 🙏 Thank You!

Thank you for contributing to YourPost! Every contribution, no matter how small, helps make the project better.

---

**Questions?** Join our [Discord](https://discord.devstroop.com) or open a discussion on GitHub!