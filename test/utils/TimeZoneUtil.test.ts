import { DEFAULT_TIME_ZONE, TimeZoneUtil } from '@mail-otter/shared/utils';
import { describe, expect, it } from 'vitest';

describe('TimeZoneUtil', () => {
  describe('isValid', () => {
    it('accepts a valid IANA time zone', () => {
      expect(TimeZoneUtil.isValid('America/Los_Angeles')).toBe(true);
      expect(TimeZoneUtil.isValid('UTC')).toBe(true);
    });

    it('rejects invalid, empty, or non-string values', () => {
      expect(TimeZoneUtil.isValid('Not/A_Zone')).toBe(false);
      expect(TimeZoneUtil.isValid('')).toBe(false);
      expect(TimeZoneUtil.isValid(null)).toBe(false);
      expect(TimeZoneUtil.isValid(undefined)).toBe(false);
    });
  });

  describe('normalize', () => {
    it('returns a valid zone unchanged', () => {
      expect(TimeZoneUtil.normalize('Europe/Berlin')).toBe('Europe/Berlin');
    });

    it('falls back to UTC for invalid input', () => {
      expect(TimeZoneUtil.normalize('garbage')).toBe(DEFAULT_TIME_ZONE);
      expect(TimeZoneUtil.normalize(null)).toBe('UTC');
    });
  });

  describe('todayInZone', () => {
    it('computes the calendar date in the requested zone', () => {
      // 2026-06-22T05:00:00Z is still 2026-06-21 in Los Angeles (UTC-7).
      const instant = new Date('2026-06-22T05:00:00Z');
      expect(TimeZoneUtil.todayInZone('America/Los_Angeles', instant)).toBe('2026-06-21');
      expect(TimeZoneUtil.todayInZone('UTC', instant)).toBe('2026-06-22');
    });

    it('falls back to UTC for an invalid zone', () => {
      const instant = new Date('2026-06-22T05:00:00Z');
      expect(TimeZoneUtil.todayInZone('garbage', instant)).toBe('2026-06-22');
    });
  });
});
