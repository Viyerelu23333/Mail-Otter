import { describe, it, expect } from 'vitest';
import { SenderFilterUtil } from '@mail-otter/backend-services/email';

describe('SenderFilterUtil', () => {
  describe('extractEmailAddress', () => {
    it('extracts address from angle-bracket format', () => {
      expect(SenderFilterUtil.extractEmailAddress('John Doe <john@example.com>')).toBe('john@example.com');
    });

    it('returns bare address as-is when no angle brackets', () => {
      expect(SenderFilterUtil.extractEmailAddress('john@example.com')).toBe('john@example.com');
    });

    it('lowercases the result', () => {
      expect(SenderFilterUtil.extractEmailAddress('JOHN@EXAMPLE.COM')).toBe('john@example.com');
    });

    it('lowercases angle-bracket format', () => {
      expect(SenderFilterUtil.extractEmailAddress('Acme Corp <Support@Acme.COM>')).toBe('support@acme.com');
    });

    it('trims whitespace', () => {
      expect(SenderFilterUtil.extractEmailAddress('  john@example.com  ')).toBe('john@example.com');
    });
  });

  describe('matchesPattern', () => {
    it('matches domain pattern when sender is from that domain', () => {
      expect(SenderFilterUtil.matchesPattern('alice@company.com', '@company.com')).toBe(true);
    });

    it('does not match domain pattern for a different domain', () => {
      expect(SenderFilterUtil.matchesPattern('alice@other.com', '@company.com')).toBe(false);
    });

    it('matches exact address', () => {
      expect(SenderFilterUtil.matchesPattern('alice@company.com', 'alice@company.com')).toBe(true);
    });

    it('does not match different exact address', () => {
      expect(SenderFilterUtil.matchesPattern('bob@company.com', 'alice@company.com')).toBe(false);
    });

    it('is case-insensitive for domain pattern', () => {
      expect(SenderFilterUtil.matchesPattern('alice@company.com', '@Company.COM')).toBe(true);
    });

    it('is case-insensitive for exact address pattern', () => {
      expect(SenderFilterUtil.matchesPattern('alice@company.com', 'Alice@Company.COM')).toBe(true);
    });
  });

  describe('shouldSkip', () => {
    it('returns skip: false when no include rules are set', () => {
      const result = SenderFilterUtil.shouldSkip('user@example.com', { includeRules: [] });
      expect(result).toEqual({ skip: false });
    });

    it('does not skip sender matching an include rule (domain)', () => {
      const result = SenderFilterUtil.shouldSkip('alice@company.com', {
        includeRules: ['@company.com'],
      });
      expect(result).toEqual({ skip: false });
    });

    it('skips sender not matching any include rule', () => {
      const result = SenderFilterUtil.shouldSkip('alice@other.com', {
        includeRules: ['@company.com'],
      });
      expect(result).toEqual({ skip: true, reason: 'Sender does not match application include filter rules.' });
    });

    it('does not skip sender matching an include rule (exact address)', () => {
      const result = SenderFilterUtil.shouldSkip('alice@company.com', {
        includeRules: ['alice@company.com'],
      });
      expect(result).toEqual({ skip: false });
    });

    it('skips sender not matching any include rule (exact address)', () => {
      const result = SenderFilterUtil.shouldSkip('bob@company.com', {
        includeRules: ['alice@company.com'],
      });
      expect(result).toEqual({ skip: true, reason: 'Sender does not match application include filter rules.' });
    });

    it('extracts email from angle-bracket From header when matching', () => {
      const result = SenderFilterUtil.shouldSkip('Alice Smith <alice@company.com>', {
        includeRules: ['@company.com'],
      });
      expect(result).toEqual({ skip: false });
    });

    it('skips sender extracted from angle-bracket header not matching include rule', () => {
      const result = SenderFilterUtil.shouldSkip('Bob Jones <bob@other.com>', {
        includeRules: ['@company.com'],
      });
      expect(result).toEqual({ skip: true, reason: 'Sender does not match application include filter rules.' });
    });
  });
});
