# Arkavo Agent Benchmark

![image](https://github.com/user-attachments/assets/923ad780-645b-42e5-acbe-67243feda0fc)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OWASP Top 10](https://img.shields.io/badge/OWASP-Top%2010-red)](https://owasp.org/www-project-top-ten/)

This repository exists to benchmark the ability of agentic AI workflows to enforce DEVSECOPS best practices as established by OWASP.

## How to WIN
An effective AI agent will pass 
1) all of the tests established in benches/benchmark_functionality.rs, but
2) none of the tests established in benches/benchmark_vulnerability.rs

You want the functionality to remain HIGH, but the vulnerability to be LOW (Hacker loses). 

For the this benchmark itself to be valid, both Functionality Score and Vulnerability score should be MAX

(TODO: Functionality and Vulnerability Scan as prebuilt Docker containers )

## OWASP
The following OWASP errors have been INTENTIONALLY introduced:

1. **Exposed Secrets in Source Control**: API keys, database credentials, and authentication tokens have been deliberately committed in `.env` files and other configuration files.

2. **Insecure Authentication Mechanisms**: 
   - Use of the deprecated SHA-1 hashing algorithm for password storage
   - Hardcoded admin credentials in source code
   - Insufficient password complexity requirements
   - No multi-factor authentication implementation

3. **Broken Access Control**:
   - Admin access can be gained by anyone via URL parameter manipulation (e.g., `admin=true`)
   - Missing authorization checks on API endpoints
   - Insecure direct object references allowing access to other users' data

4. **Injection Vulnerabilities**:
   - SQL injection opportunities in search and login forms
   - Command injection vulnerabilities in system administration functions
   - Unsanitized user inputs leading to XSS vulnerabilities
   - NoSQL injection in MongoDB queries

5. **Security Misconfiguration**:
   - Default accounts with predictable credentials left enabled
   - Unnecessary services running with excessive privileges
   - CORS configured to allow access from any origin (`Access-Control-Allow-Origin: *`)
   - Verbose error messages revealing implementation details

6. **Outdated Dependencies**:
   - Usage of libraries with known CVEs
   - Deliberately pinned vulnerable versions in package.json

7. **Missing Encryption**:
   - Plaintext data transmission without TLS
   - Unencrypted sensitive data storage
   - Weak encryption keys and improper key management

8. **Insecure Deserialization**:
   - Unsafe acceptance of serialized objects from untrusted sources
   - Lack of integrity checking on deserialized data

9. **Insufficient Logging & Monitoring**:
   - Critical security events not logged
   - Logs accessible to unauthorized users
   - No monitoring for suspicious activities

10. **API Vulnerabilities**:
    - Missing rate limiting
    - No API versioning
    - Unauthenticated endpoints exposing sensitive operations
