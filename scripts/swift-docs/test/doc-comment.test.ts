import { describe, it, expect } from "vitest";
import { parseDocComment } from "../src/doc-comment";

describe("parseDocComment", () => {
  it("returns empty summary for empty input", () => {
    expect(parseDocComment([])).toEqual({ summary: [] });
  });

  it("parses a plain single-line summary", () => {
    const result = parseDocComment([{ text: "Signs in the user." }]);
    expect(result.summary).toEqual([{ kind: "text", text: "Signs in the user." }]);
    expect(result.blockTags).toBeUndefined();
  });

  it("accumulates multiple plain lines into summary", () => {
    const result = parseDocComment([
      { text: "First line." },
      { text: "Second line." },
    ]);
    expect(result.summary).toEqual([
      { kind: "text", text: "First line." },
      { kind: "text", text: "Second line." },
    ]);
  });

  it("stops summary at first tag line; blank separator is discarded", () => {
    const result = parseDocComment([
      { text: "Signs in the user." },
      { text: "" },
      { text: "- Parameter email: The email." },
    ]);
    expect(result.summary).toEqual([{ kind: "text", text: "Signs in the user." }]);
  });

  it("parses - Parameter tag (traditional Swift style)", () => {
    const result = parseDocComment([
      { text: "Does something." },
      { text: "- Parameter email: The user email." },
    ]);
    expect(result.blockTags).toEqual([
      { tag: "@param", name: "email", content: [{ kind: "text", text: "The user email." }] },
    ]);
  });

  it("parses - Returns tag", () => {
    const result = parseDocComment([
      { text: "Does something." },
      { text: "- Returns: The session." },
    ]);
    expect(result.blockTags).toEqual([
      { tag: "@returns", content: [{ kind: "text", text: "The session." }] },
    ]);
  });

  it("parses - Throws tag", () => {
    const result = parseDocComment([{ text: "- Throws: AuthError on failure." }]);
    expect(result.blockTags).toEqual([
      { tag: "@throws", content: [{ kind: "text", text: "AuthError on failure." }] },
    ]);
  });

  it("parses DocC @Parameter style", () => {
    const result = parseDocComment([{ text: "@Parameter email The user email." }]);
    expect(result.blockTags).toEqual([
      { tag: "@param", name: "email", content: [{ kind: "text", text: "The user email." }] },
    ]);
  });

  it("parses DocC @Returns style", () => {
    const result = parseDocComment([{ text: "@Returns The session." }]);
    expect(result.blockTags).toEqual([
      { tag: "@returns", content: [{ kind: "text", text: "The session." }] },
    ]);
  });

  it("passes unknown dash-tags through with lowercased tag name", () => {
    const result = parseDocComment([{ text: "- Note: Be careful here." }]);
    expect(result.blockTags).toEqual([
      { tag: "@note", content: [{ kind: "text", text: "Be careful here." }] },
    ]);
  });

  it("parses multiple params and returns together", () => {
    const result = parseDocComment([
      { text: "Signs in." },
      { text: "" },
      { text: "- Parameter email: The email." },
      { text: "- Parameter password: The password." },
      { text: "- Returns: The session." },
    ]);
    expect(result.blockTags).toHaveLength(3);
    expect(result.blockTags![0]).toEqual({
      tag: "@param", name: "email", content: [{ kind: "text", text: "The email." }],
    });
    expect(result.blockTags![1]).toEqual({
      tag: "@param", name: "password", content: [{ kind: "text", text: "The password." }],
    });
    expect(result.blockTags![2]).toEqual({
      tag: "@returns", content: [{ kind: "text", text: "The session." }],
    });
  });
});
