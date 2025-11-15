# CLAUDE.md - AI Assistant Guide for Locafoto

**Last Updated:** 2025-11-15
**Repository:** locafoto
**Status:** New Project (Initial Setup)

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Repository Structure](#repository-structure)
3. [Development Workflows](#development-workflows)
4. [Code Conventions](#code-conventions)
5. [Testing Standards](#testing-standards)
6. [Git Practices](#git-practices)
7. [AI Assistant Guidelines](#ai-assistant-guidelines)
8. [Security Considerations](#security-considerations)
9. [Common Tasks](#common-tasks)

---

## Project Overview

### What is Locafoto?

Locafoto is a [photo management/organization system - to be defined]. This project aims to [purpose to be defined based on initial development].

### Tech Stack

**Status:** To be determined during initial development

Expected components may include:
- **Frontend:** [TBD - React, Vue, Svelte, etc.]
- **Backend:** [TBD - Node.js, Python, Go, etc.]
- **Database:** [TBD - PostgreSQL, MySQL, SQLite, etc.]
- **Storage:** [TBD - Local filesystem, S3, etc.]
- **Build Tools:** [TBD]

### Key Features (Planned)

- Photo upload and storage
- Photo organization and tagging
- Photo viewing and browsing
- [Additional features to be defined]

---

## Repository Structure

### Current Structure

```
locafoto/
├── .git/              # Git repository data
└── CLAUDE.md          # This file
```

### Planned Structure

As the project develops, the structure should follow these guidelines:

```
locafoto/
├── .github/           # GitHub workflows and templates
│   ├── workflows/     # CI/CD pipelines
│   └── ISSUE_TEMPLATE/
├── docs/              # Documentation
├── src/               # Source code
│   ├── components/    # Reusable components
│   ├── services/      # Business logic
│   ├── utils/         # Utility functions
│   └── types/         # Type definitions
├── tests/             # Test files
│   ├── unit/
│   ├── integration/
│   └── e2e/
├── scripts/           # Build and deployment scripts
├── config/            # Configuration files
├── public/            # Static assets
├── .gitignore
├── README.md
├── CLAUDE.md          # This file
└── [package.json/requirements.txt/go.mod/etc.]
```

**Key Principles:**
- Keep source code separate from tests
- Group related functionality together
- Maintain clear separation of concerns
- Use descriptive directory names

---

## Development Workflows

### Initial Setup

When setting up the project for the first time:

1. **Determine tech stack** based on requirements
2. **Initialize package manager** (npm, pip, cargo, etc.)
3. **Set up linting and formatting** (ESLint, Prettier, Black, etc.)
4. **Configure git hooks** for pre-commit checks
5. **Set up CI/CD** pipeline basics
6. **Create initial documentation** (README, contributing guidelines)

### Feature Development

1. **Create feature branch** from main:
   ```bash
   git checkout -b feature/descriptive-name
   ```

2. **Develop with tests:**
   - Write tests first (TDD) or alongside code
   - Ensure all tests pass before committing
   - Maintain test coverage above 80%

3. **Commit frequently** with clear messages:
   ```bash
   git commit -m "feat: add photo upload endpoint"
   ```

4. **Push and create PR:**
   ```bash
   git push -u origin feature/descriptive-name
   ```

### Code Review Process

- All changes require review before merging
- Address review comments promptly
- Ensure CI/CD checks pass
- Squash commits if needed for clean history

---

## Code Conventions

### General Principles

1. **Clarity over cleverness** - Write code that's easy to understand
2. **DRY (Don't Repeat Yourself)** - Extract common patterns
3. **SOLID principles** - Follow object-oriented best practices
4. **Consistent naming** - Use established patterns throughout
5. **Comments for why, not what** - Code should be self-documenting

### Naming Conventions

**To be established based on chosen tech stack:**

- **Files:** kebab-case, PascalCase, or snake_case
- **Variables:** camelCase or snake_case
- **Constants:** UPPER_SNAKE_CASE
- **Classes:** PascalCase
- **Functions:** camelCase or snake_case
- **Components:** PascalCase

### File Organization

- **One component/class per file** (unless tightly coupled)
- **Group related files** in directories
- **Export from index files** for clean imports
- **Keep files under 300 lines** when possible

### Code Style

- **Indentation:** [2 spaces / 4 spaces / tabs - TBD]
- **Line length:** Max 100-120 characters
- **Semicolons:** [Required / Optional - TBD]
- **Quotes:** [Single / Double - TBD]
- **Trailing commas:** Recommended for multi-line structures

---

## Testing Standards

### Test Coverage Requirements

- **Minimum coverage:** 80% overall
- **Critical paths:** 100% coverage
- **New features:** Must include tests
- **Bug fixes:** Add regression tests

### Test Structure

```
describe('Feature/Component Name', () => {
  describe('specific functionality', () => {
    it('should handle expected case', () => {
      // Arrange
      // Act
      // Assert
    });

    it('should handle edge case', () => {
      // Test edge cases
    });

    it('should handle error case', () => {
      // Test error handling
    });
  });
});
```

### Test Types

1. **Unit Tests** - Test individual functions/components in isolation
2. **Integration Tests** - Test component interactions
3. **E2E Tests** - Test complete user workflows
4. **Performance Tests** - For critical paths (photo upload, processing)

### Testing Best Practices

- Test behavior, not implementation
- Use meaningful test descriptions
- Keep tests independent and isolated
- Mock external dependencies
- Use factories for test data

---

## Git Practices

### Branch Naming

- **Feature:** `feature/short-description`
- **Bug fix:** `fix/issue-number-description`
- **Hotfix:** `hotfix/critical-issue`
- **Refactor:** `refactor/what-is-refactored`
- **Documentation:** `docs/what-is-documented`
- **Claude branches:** `claude/claude-md-*` (auto-generated)

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Formatting, missing semicolons, etc.
- `refactor`: Code restructuring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(upload): add drag-and-drop photo upload
fix(auth): resolve token expiration issue
docs(readme): update installation instructions
refactor(storage): simplify file path handling
```

### Pull Requests

**PR Title Format:**
```
[TYPE] Brief description of changes
```

**PR Description Must Include:**
- Summary of changes
- Related issue numbers
- Testing performed
- Screenshots (for UI changes)
- Migration steps (if needed)
- Checklist of completed items

**Before Merging:**
- [ ] All tests pass
- [ ] Code review approved
- [ ] Documentation updated
- [ ] No merge conflicts
- [ ] CI/CD pipeline green

---

## AI Assistant Guidelines

### Core Responsibilities

As an AI assistant working on this project, you should:

1. **Understand context first** - Read relevant files before making changes
2. **Follow established patterns** - Match existing code style
3. **Test your changes** - Write and run tests
4. **Document as you go** - Update docs with changes
5. **Commit logically** - Group related changes
6. **Communicate clearly** - Explain what and why

### Before Making Changes

1. **Explore the codebase** to understand current implementation
2. **Check for existing solutions** to similar problems
3. **Review recent commits** to understand recent work
4. **Read relevant documentation** in docs/ or comments
5. **Plan your approach** before writing code

### When Implementing Features

1. **Start with tests** - Define expected behavior
2. **Implement incrementally** - Small, working steps
3. **Refactor as needed** - Clean up after it works
4. **Update documentation** - README, CLAUDE.md, inline comments
5. **Run full test suite** - Ensure nothing broke

### When Fixing Bugs

1. **Reproduce the issue** first
2. **Write a failing test** that captures the bug
3. **Fix the issue** with minimal changes
4. **Verify the test passes** and no regressions
5. **Document the fix** in commit message

### Code Quality Checklist

Before committing, verify:

- [ ] Code follows project conventions
- [ ] No commented-out code (unless intentional with explanation)
- [ ] No console.log/print statements (use proper logging)
- [ ] No hard-coded values that should be configurable
- [ ] Error handling is comprehensive
- [ ] Edge cases are handled
- [ ] Security best practices followed
- [ ] Performance considerations addressed
- [ ] Tests are passing
- [ ] Documentation is updated

### File Operations

**Prefer editing over creating:**
- Always check if a file exists before creating new ones
- Update existing files rather than duplicating functionality
- Only create new files when truly necessary

**When reading files:**
- Use the Read tool for specific files
- Use Glob for finding files by pattern
- Use Grep for searching code
- Use Task/Explore for broader code exploration

**When editing files:**
- Read the file first to understand context
- Preserve existing formatting and style
- Make surgical changes, not wholesale rewrites
- Verify changes don't break dependent code

### Security Awareness

**Always check for:**
- SQL injection vulnerabilities
- XSS (Cross-Site Scripting) risks
- CSRF token validation
- Authentication/authorization checks
- Sensitive data exposure
- Insecure dependencies
- Path traversal vulnerabilities
- Command injection risks

**Photo-specific security:**
- Validate file types (not just extensions)
- Limit file sizes
- Sanitize metadata
- Prevent directory traversal in paths
- Scan for malware in uploads
- Implement rate limiting
- Validate image dimensions

### Performance Considerations

**For photo operations:**
- Use lazy loading for image galleries
- Implement progressive image loading
- Generate and cache thumbnails
- Optimize image formats (WebP, AVIF)
- Use CDN for static assets
- Implement pagination for large sets
- Use database indexing appropriately
- Monitor memory usage for large files

---

## Security Considerations

### Authentication & Authorization

- Implement proper user authentication
- Use JWT or session-based auth appropriately
- Validate permissions on all operations
- Never trust client-side validation alone

### Data Protection

- Encrypt sensitive data at rest
- Use HTTPS for all communications
- Sanitize all user inputs
- Implement proper CORS policies
- Use environment variables for secrets
- Never commit credentials to git

### File Upload Security

- Validate file types using magic numbers
- Restrict file sizes
- Scan uploaded files for malware
- Store files outside web root
- Use unique, non-guessable filenames
- Implement virus scanning
- Strip dangerous metadata

### Database Security

- Use parameterized queries (prevent SQL injection)
- Implement least-privilege access
- Regular backup procedures
- Encrypt sensitive fields
- Audit logging for sensitive operations

---

## Common Tasks

### Adding a New Feature

```bash
# 1. Create feature branch
git checkout -b feature/photo-tagging

# 2. Implement with tests
# [write code and tests]

# 3. Run tests
[npm test / pytest / go test]

# 4. Commit changes
git add .
git commit -m "feat(tags): add photo tagging functionality"

# 5. Push and create PR
git push -u origin feature/photo-tagging
```

### Running Tests

```bash
# Run all tests
[TBD based on tech stack]

# Run specific test file
[TBD]

# Run with coverage
[TBD]

# Watch mode for development
[TBD]
```

### Building for Production

```bash
# Install dependencies
[TBD]

# Run linter
[TBD]

# Run tests
[TBD]

# Build
[TBD]

# Deploy
[TBD]
```

### Database Operations

```bash
# Run migrations
[TBD]

# Seed database
[TBD]

# Backup database
[TBD]

# Reset database
[TBD]
```

---

## Project-Specific Notes

### Photo Processing Pipeline

**To be defined:**
- Upload validation
- Storage strategy
- Thumbnail generation
- Metadata extraction
- Format conversion
- Optimization pipeline

### Storage Strategy

**To be defined:**
- Local filesystem structure
- Cloud storage integration
- Backup procedures
- Retention policies

### API Design

**To be defined:**
- REST vs GraphQL
- Endpoint structure
- Authentication flow
- Rate limiting
- Error responses

---

## Updating This Document

This CLAUDE.md file should be updated whenever:

1. **Tech stack is chosen** - Update all [TBD] sections
2. **Architecture decisions are made** - Document the rationale
3. **New patterns emerge** - Capture and standardize them
4. **Conventions change** - Keep this as source of truth
5. **New tools are added** - Document their usage
6. **Common issues are found** - Add troubleshooting section

### Update Process

1. Make changes to CLAUDE.md
2. Update "Last Updated" date at top
3. Commit with message: `docs(claude): [description of update]`
4. Announce significant changes to team

---

## Additional Resources

### Documentation to Create

- [ ] README.md - Project overview and quick start
- [ ] CONTRIBUTING.md - Contribution guidelines
- [ ] API.md - API documentation
- [ ] ARCHITECTURE.md - System architecture
- [ ] DEPLOYMENT.md - Deployment procedures
- [ ] TROUBLESHOOTING.md - Common issues and solutions

### External Resources

- [Project management tool - TBD]
- [Design system - TBD]
- [API documentation - TBD]
- [Deployment dashboard - TBD]

---

## Questions or Issues?

If you encounter ambiguity while working on this project:

1. **Check existing code** for patterns
2. **Review recent commits** for context
3. **Ask clarifying questions** rather than guessing
4. **Document decisions** for future reference
5. **Update this guide** with answers

---

**Remember:** The goal is to build a robust, maintainable, and secure photo management system. When in doubt, prioritize security, user experience, and code quality over speed of development.
