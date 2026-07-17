#include <string.h>

#include "cmark-gfm.h"
#include "cmark-gfm-extension_api.h"
#include "cmark-gfm-core-extensions.h"

int main(void) {
  static const char markdown[] = "| a | b |\n| - | - |\n| 1 | 2 |\n\n~~done~~\n";
  cmark_node *document;
  cmark_parser *parser;
  cmark_syntax_extension *table;

  cmark_gfm_core_extensions_ensure_registered();
  table = cmark_find_syntax_extension("table");
  if (table == NULL) {
    return 1;
  }

  parser = cmark_parser_new(CMARK_OPT_DEFAULT);
  if (parser == NULL || !cmark_parser_attach_syntax_extension(parser, table)) {
    cmark_parser_free(parser);
    return 2;
  }

  cmark_parser_feed(parser, markdown, strlen(markdown));
  document = cmark_parser_finish(parser);
  cmark_parser_free(parser);
  if (document == NULL) {
    return 3;
  }
  cmark_node_free(document);
  return 0;
}
