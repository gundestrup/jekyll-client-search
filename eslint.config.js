"use strict";

const globals = require("globals");

module.exports = [
    {
        languageOptions: {
            ecmaVersion: 2022,
            sourceType: "script",
            globals: {
                ...globals.browser,
                ...globals.node
            }
        },
        rules: {
            "no-undef": "error",
            "no-unused-vars": ["warn", { argsIgnorePattern: "^_", caughtErrorsIgnorePattern: "^_" }],
            eqeqeq: ["warn", "smart"],
            semi: ["error", "always"],
            quotes: ["warn", "double", { avoidEscape: true }],
            "comma-dangle": ["warn", "never"]
        }
    },
    {
        files: ["assets/**/*.js"],
        rules: {
            "no-var": "off",
            indent: ["warn", 4, { SwitchCase: 1 }]
        }
    },
    {
        files: ["test/**/*.js"],
        languageOptions: {
            globals: {
                ...globals.node,
                describe: "readonly",
                test: "readonly",
                it: "readonly",
                assert: "readonly",
                before: "readonly",
                after: "readonly",
                beforeEach: "readonly",
                afterEach: "readonly"
            }
        },
        rules: {
            "no-var": "off",
            indent: ["warn", 4, { SwitchCase: 1 }]
        }
    },
    {
        ignores: ["node_modules/**", "_site/**", "vendor/**"]
    }
];
