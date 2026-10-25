# Wire format

This extension does not define the id format; it follows it. The normative
statement of what a UXID string is - the alphabet, the bit packing, the sizes,
the prefix grammar, deterministic and monotonic bodies, and what a decoder
reads back - is the reference specification in uxid-ex:

- [`guides/wire-format.md` at the tag `v2.10.0`](https://github.com/riddler/uxid-ex/blob/v2.10.0/guides/wire-format.md)

The tag is the one `conformance/SOURCE.json` names. That file also records
the commit and the hash of the vendored conformance corpus, the cases every
implementation of the format passes; the cases in `conformance/` are the
arbiter where the specification and a reference implementation could be read
two ways. When the corpus is bumped to a newer tag, `SOURCE.json` and this
pointer move together.

Where this extension makes a choice the specification leaves open, the
README states it: the SQLSTATE and message of each refusal, `invalid_argument`
for an argument outside the corpus's error names, and the session-only
monotonic order.
