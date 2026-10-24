# comment.code samples (draft 3.2 heuristic)

Seeded random sample of 10 detected segments per language, for a precision eyeball. Text is truncated to 80 chars and multi-line comments show their first line.

## python: 8 of 1597 comments (0.5%)

- `src/flask/sansio/app.py:395` `#:        def to_python(self, value):`
- `src/flask/sansio/app.py:396` `#:            return value.split(',')`
- `src/flask/sansio/app.py:398` `#:            return ','.join(super(ListConverter, self).to_url(value)`
- `src/flask/helpers.py:343` `#     session.setdefault('_flashes', []).append((category, message))`
- `src/flask/sansio/app.py:394` `#:    class ListConverter(BaseConverter):`
- `src/flask/sansio/app.py:401` `#:    app = Flask(__name__)`
- `src/flask/sansio/app.py:397` `#:        def to_url(self, values):`
- `src/flask/testing.py:223` `# isinstance(args[0], BaseRequest)`

## javascript: 8 of 888 comments (0.9%)

- `lib/core/AxiosError.js:27` `// (case-insensitive) listed in `redactKeys` with REDACTED. Walks through arrays`
- `lib/application.js:353` `// app.get(setting)`
- `examples/route-map/index.js:18` `// { '/path': { ... }}`
- `examples/view-locals/index.js:128` `/*`
- `examples/view-locals/index.js:141` `/*`
- `examples/route-map/index.js:22` `// get: function(){ ... }`
- `lib/application.js:474` `// app.get(setting)`
- `examples/view-locals/index.js:115` `/*`

## typescript: 43 of 966 comments (4.5%)

- `d/src/v3/tests/async-refinements.test.ts:24` `// expect.assertions(2);`
- `src/v4/classic/tests/error-utils.test.ts:246` `// const error = _error as z.ZodError;`
- `zod/src/v4/mini/tests/prototypes.test.ts:19` `// expectTypeOf<typeof result>().toEqualTypeOf<string>();`
- `packages/zod/src/v3/tests/tuple.test.ts:86` `//   const result = z`
- `s/zod/src/v3/tests/async-parsing.test.ts:124` `// if (!badResult.success) expect(badResult.error).toBeInstanceOf(z.ZodError);`
- `s/zod/src/v3/tests/async-parsing.test.ts:384` `// await result.then((r) => {`
- `packages/zod/src/v3/tests/tuple.test.ts:53` `//     expect(err.issues.length).toEqual(3);`
- `packages/zod/src/v3/tests/tuple.test.ts:49` `// try {`
- `src/v4/classic/tests/error-utils.test.ts:326` `// });`
- `packages/zod/src/v4/classic/parse.ts:26` `// _params?: { callee?: core.util.AnyFunc; Err?: core.$ZodErrorClass }`

## rust: 7 of 1076 comments (0.7%)

- `src/syntax_mapping/builtin.rs:23` `// enum BuiltinMatcher {`
- `src/syntax_mapping/builtin.rs:26` `// }`
- `crates/printer/src/jsont.rs:214` `// use base64::engine::{general_purpose::STANDARD, Engine};`
- `crates/printer/src/jsont.rs:215` `// let encoded = STANDARD.encode(bytes);`
- `src/syntax_mapping/builtin.rs:25` `//     Dynamic(Lazy<Option<String>>),`
- `src/syntax_mapping/builtin.rs:24` `//     Fixed(&'static str),`
- `crates/printer/src/standard.rs:1210` `// self.write_trim(line)?;`

## go: 34 of 2348 comments (1.4%)

- `gin_integration_test.go:428` `// 	}`
- `gin_integration_test.go:31` `// params[2]=response body (custom compare content)  default:"it worked"`
- `routergroup.go:231` `//	router.Static("/static", "/var/www")`
- `binding/validate_test.go:170` `// assert.Equal(t, origin, test)`
- `routergroup.go:65` `//		q.QUERY("/search", handler)`
- `errors.go:129` `//	c.Errors.Errors() // == []string{"first", "second", "third"}`
- `routergroup.go:66` `//	}`
- `routergroup.go:64` `//	if q, ok := routes.(gin.IQueryRoutes); ok {`
- `completions.go:620` `// 	completions = append(completions, CompletionWithDesc(flagName, flag.Usage))`
- `errors.go:126` `//	c.Error(errors.New("first"))`

## c: 5 of 1987 comments (0.3%)

- `src/anet.c:464` `/* strlen("65535") + 1; */`
- `src/siphash.c:339` `/* printf("fail for %d bytes\n", i); */`
- `src/sds.h:198` `/* sdsalloc() = sdsavail() + sdslen() */`
- `src/anet.c:597` `/* strlen("65535") */`
- `src/sparkline.c:44` `/* ----------------------------------------------------------------------------`

## lua: 40 of 1134 comments (3.5%)

- `lua/telescope/actions/set.lua:53` `--     action_state.get_current_history():append(`
- `lua/telescope/config/resolve.lua:299` `-- }`
- `lua/telescope/config/resolve.lua:296` `-- borderchars = {`
- `lua/telescope/builtin/__internal.lua:635` `-- map('i', '<C-i>', actions.insert_value, { expr = true })`
- `lua/telescope/utils.lua:421` `--     print(opts.example, opts.another)`
- `lua/telescope/config/resolve.lua:290` `--   preview = {...},`
- `lescope/finders/async_oneshot_finder.lua:42` `--   writer = job_opts.writer`
- `runtime/lua/vim/lsp/handlers.lua:727` `--  code: integer;`
- `lua/tests/automated/action_spec.lua:493` `--  In config, we have { ["<CR>"] = actions.select, ... }`
- `lua/telescope/config/resolve.lua:298` `--   prompt = {...},`

## bash: 29 of 2080 comments (1.4%)

- `mes/rainbowbrite/rainbowbrite.theme.bash:13` `# PS1="${red?}$(scm_char) ${purple?}\u@\h${reset_color?}:${blue?}\w${yellow?}$(s`
- `template/bashrc.template.bash:43` `#BASH_IT_PROJECT_PATHS="${HOME}/Projects:/Volumes/work/src"`
- `template/bashrc.template.bash:31` `#GIT_HOSTING='git@git.domain.com'`
- `plugins/available/postgres.plugin.bash:73` `# function postgres_syslog {`
- `etion/available/git_flow.completion.bash:38` `#         flow)        _git_flow ;;`
- `template/bashrc.template.bash:46` `#SCM_CHECK=true`
- `template/bashrc.template.bash:24` `#BASH_IT_REMOTE='bash-it'`
- `template/bashrc.template.bash:49` `#SCM_GIT_GITSTATUS_DIR="$HOME/gitstatus"`
- `pletion/available/fabric.completion.bash:109` `#     opts="${__FAB_COMPLETION_SHORT_OPT}"`
- `nvm.sh:4290` `# NVM_NO_SOURCE_FALLBACK=1 makes `nvm install` behave as if `-b` were always pas`

## elisp: 5 of 2989 comments (0.2%)

- `company.el:46` `;; (defun company-my-backend (command &optional arg &rest ignored)`
- `lisp/magit.el:29` `;;     (with-editor   "3.5"))`
- `lisp/magit.el:26` `;;     (magit-section "4.7")`
- `lisp/magit.el:24` `;;     (cond-let      "1.1")`
- `lisp/magit-process.el:705` `;t=pty nil=pipe`

## java: 44 of 861 comments (5.1%)

- `apache/commons/lang3/ConversionTest.java:783` `// assertArrayEquals(new boolean[]{false, false, false, true, true, false, true,`
- `in/java/com/google/gson/TypeAdapter.java:109` `//   TypeAdapter<Graph> graphAdapter = gson.getAdapter(Graph.class);`
- `nctional/GsonVersionDiagnosticsTest.java:91` `// System.err.println(version);`
- `apache/commons/lang3/ConversionTest.java:218` `// assertEquals('7', Conversion.BinaryToHexDigitMsb0(longArray, 5));`
- `apache/commons/lang3/ConversionTest.java:1155` `// assertArrayEquals(new boolean[]{false, false, false, true, true, false, true,`
- `in/java/com/google/gson/TypeAdapter.java:110` `//   Graph graph = graphAdapter.fromJson(json);`
- `apache/commons/lang3/ConversionTest.java:1687` `// assertArrayEquals(new`
- `apache/commons/lang3/ConversionTest.java:200` `// assertEquals('1', Conversion.BinaryToHexDigitMsb0(shortArray, 2));`
- `son/internal/bind/util/ISO8601Utils.java:257` `// String timezoneId = "UTC" + timezoneOffset;`
- `m/google/gson/functional/ObjectTest.java:755` `// json = {"r":{"r": ... {"r":null} ... }}`
