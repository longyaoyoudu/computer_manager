$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

Describe "Build-CMLLMRequestBody" {
    It 'should include thinking=disabled when configured (MiniMax-M3)' {
        $cfg = @{
            llm = @{
                base_url = 'https://api.minimaxi.com/v1'
                api_key = 'sk-test'
                model = 'MiniMax-M3'
                temperature = 0.2
                timeout_seconds = 60
                max_response_tokens = 2000
                thinking = @{ type = 'disabled' }
            }
        }
        $body = Build-CMLLMRequestBody -Config $cfg -UserMessage 'hello'
        $obj = $body | ConvertFrom-Json
        $obj.thinking.type | Should Be 'disabled'
        $obj.model | Should Be 'MiniMax-M3'
        $obj.tool_choice.function.name | Should Be 'submit_diagnosis'
        $obj.messages.Count | Should Be 2
        $obj.messages[0].role | Should Be 'system'
        $obj.messages[1].role | Should Be 'user'
    }

    It 'should include thinking=adaptive when configured' {
        $cfg = @{
            llm = @{
                base_url = 'https://api.minimaxi.com/v1'
                api_key = 'sk-test'
                model = 'MiniMax-M3'
                temperature = 0.2
                timeout_seconds = 60
                max_response_tokens = 2000
                thinking = @{ type = 'adaptive' }
            }
        }
        $body = Build-CMLLMRequestBody -Config $cfg -UserMessage 'hi'
        ($body | ConvertFrom-Json).thinking.type | Should Be 'adaptive'
    }

    It 'should omit thinking field when not configured (backward compat)' {
        $cfg = @{
            llm = @{
                base_url = 'https://api.openai.com/v1'
                api_key = 'sk-test'
                model = 'gpt-4o-mini'
                temperature = 0.2
                timeout_seconds = 60
                max_response_tokens = 2000
            }
        }
        $body = Build-CMLLMRequestBody -Config $cfg -UserMessage 'hi'
        $obj = $body | ConvertFrom-Json
        # Use -contains + Should Be instead of Pester 3.4's Should Not Contain, which
        # misroutes array operands through its file-containment path.
        ($obj.PSObject.Properties.Name -contains 'thinking') | Should Be $false
    }
}

Describe "ConvertFrom-CMLLMResponse (tool_calls)" {
    It 'should parse tool_calls form' {
        $raw = @{
            choices = @(@{
                message = @{
                    tool_calls = @(@{
                        function = @{
                            name = 'submit_diagnosis'
                            arguments = '{"analysis":"x","root_cause":"y","risk_level":"low","commands":[{"id":1,"description":"d","command":"Get-Service"}]}'
                        }
                    })
                }
            })
        }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be 'x'
        $r.root_cause | Should Be 'y'
        $r.risk_level | Should Be 'low'
        $r.commands[0].command | Should Be 'Get-Service'
    }
}

Describe "ConvertFrom-CMLLMResponse (text JSON fallback)" {
    It 'should parse markdown-wrapped JSON' {
        $raw = @{
            choices = @(@{
                message = @{
                    content = @'
```json
{"analysis":"a","root_cause":"b","risk_level":"medium","commands":[]}
```
'@
                }
            })
        }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be 'a'
        $r.risk_level | Should Be 'medium'
    }

    It 'should parse bare JSON' {
        $raw = @{
            choices = @(@{
                message = @{
                    content = '{"analysis":"plain","root_cause":"rc","risk_level":"high","commands":[]}'
                }
            })
        }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be 'plain'
    }

    It 'should fall back to text' {
        $raw = @{
            choices = @(@{
                message = @{
                    content = 'not JSON text'
                }
            })
        }
        $r = ConvertFrom-CMLLMResponse -Raw $raw -FallbackText
        $r.analysis | Should Be 'not JSON text'
    }
}

Describe "ConvertFrom-CMLLMResponse (edge cases)" {
    It 'should throw when choices is missing' {
        $raw = @{ error = 'rate limited' }
        { ConvertFrom-CMLLMResponse -Raw $raw } | Should Throw
    }

    It 'should take first tool_call when multiple present' {
        $raw = @{
            choices = @(@{
                message = @{
                    tool_calls = @(
                        @{ function = @{ name = 'submit_diagnosis'; arguments = '{"analysis":"first","root_cause":"r","risk_level":"low","commands":[]}' } },
                        @{ function = @{ name = 'submit_diagnosis'; arguments = '{"analysis":"second","root_cause":"r","risk_level":"low","commands":[]}' } }
                    )
                }
            })
        }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be 'first'
    }

    It 'should fall back to text when tool_call arguments are malformed' {
        $raw = @{
            choices = @(@{
                message = @{
                    tool_calls = @(@{ function = @{ name = 'submit_diagnosis'; arguments = '{not valid json' } })
                    content = 'plain text response'
                }
            })
        }
        $r = ConvertFrom-CMLLMResponse -Raw $raw -FallbackText
        $r.analysis | Should Be 'plain text response'
    }

    It 'should throw when no parseable content' {
        $raw = @{ choices = @(@{ message = @{ content = 'no braces here' } }) }
        { ConvertFrom-CMLLMResponse -Raw $raw } | Should Throw
    }
}

Describe "ConvertFrom-CMLLMResponse (balanced JSON extractor)" {
    It 'should extract JSON when text contains PowerShell scriptblocks with braces' {
        $content = @'
Here is my analysis. The fix involves a scriptblock: `Get-ChildItem | Where-Object {$_.Length -gt 100MB} | Select-Object FullName,Length`.
More prose with stray `}` characters.
```json
{"analysis":"disk full","root_cause":"SoftwareDistribution huge","risk_level":"low","commands":[]}
```
Trailing text with `}` braces.
'@
        $raw = @{ choices = @(@{ message = @{ content = $content } }) }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be 'disk full'
        $r.root_cause | Should Be 'SoftwareDistribution huge'
        $r.risk_level | Should Be 'low'
    }

    It 'should extract bare JSON even when prose contains nested braces' {
        $content = 'Analysis: tried `{ $_.x }` scriptblock. Result is {"analysis":"a","root_cause":"b","risk_level":"medium","commands":[]}. Done.'
        $raw = @{ choices = @(@{ message = @{ content = $content } }) }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be 'a'
        $r.risk_level | Should Be 'medium'
    }

    It 'should strip <think> blocks before extracting JSON' {
        $content = '<think>model reasoning with {braces} and `{$_.stuff}` here</think>{"analysis":"x","root_cause":"y","risk_level":"low","commands":[]}'
        $raw = @{ choices = @(@{ message = @{ content = $content } }) }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be 'x'
    }

    It 'should still throw when no balanced JSON object exists' {
        $content = 'analysis with `{ stray:brace` but no balanced JSON object anywhere'
        $raw = @{ choices = @(@{ message = @{ content = $content } }) }
        { ConvertFrom-CMLLMResponse -Raw $raw } | Should Throw
    }

    It 'should not be fooled by braces inside JSON string values' {
        $content = 'Pre text. {"analysis":"with } inside string","root_cause":"b","risk_level":"low","commands":[]} Post.'
        $raw = @{ choices = @(@{ message = @{ content = $content } }) }
        $r = ConvertFrom-CMLLMResponse -Raw $raw
        $r.analysis | Should Be 'with } inside string'
    }
}

Describe "Test-CMLLMResponseThinkingOnly" {
    It 'returns true when content is only <think> block' {
        $raw = @{ choices = @(@{
            message = @{ content = '<think>model thought for a while but never produced output</think>' }
        }) }
        Test-CMLLMResponseThinkingOnly -Raw $raw | Should Be $true
    }

    It 'returns true when content is empty and no tool_calls' {
        $raw = @{ choices = @(@{
            message = @{ content = '' }
        }) }
        Test-CMLLMResponseThinkingOnly -Raw $raw | Should Be $true
    }

    It 'returns false when tool_calls is present' {
        $raw = @{ choices = @(@{
            message = @{
                content = '<think>ignored when tool_calls present</think>'
                tool_calls = @(@{ function = @{ name = 'submit_diagnosis'; arguments = '{}' } })
            }
        }) }
        Test-CMLLMResponseThinkingOnly -Raw $raw | Should Be $false
    }

    It 'returns false when content has prose after <think>' {
        $raw = @{ choices = @(@{
            message = @{ content = "<think>reasoning</think>Real answer here." }
        }) }
        Test-CMLLMResponseThinkingOnly -Raw $raw | Should Be $false
    }

    It 'returns false when choices is missing' {
        $raw = @{ error = 'rate limited' }
        Test-CMLLMResponseThinkingOnly -Raw $raw | Should Be $false
    }
}

Describe "ConvertFrom-CMLLMResponse (FallbackText strips <think>)" {
    It 'should strip <think> block from analysis when prose follows' {
        $content = "<think>this was the model thinking</think>User-facing answer."
        $raw = @{ choices = @(@{ message = @{ content = $content } }) }
        $r = ConvertFrom-CMLLMResponse -Raw $raw -FallbackText
        $r.analysis | Should Be 'User-facing answer.'
        ($r.analysis -notmatch '<think>') | Should Be $true
        $r.risk_level | Should Be 'unknown'
    }

    It 'should preserve prose around <think> when FallbackText triggers' {
        $content = "<think>reasoning</think>User-facing answer here."
        $raw = @{ choices = @(@{ message = @{ content = $content } }) }
        $r = ConvertFrom-CMLLMResponse -Raw $raw -FallbackText
        $r.analysis | Should Be 'User-facing answer here.'
    }

    It 'should fall back to original text when stripping leaves nothing' {
        $content = '<think>only thinking, no prose, no JSON, no tool_calls</think>'
        $raw = @{ choices = @(@{ message = @{ content = $content } }) }
        $r = ConvertFrom-CMLLMResponse -Raw $raw -FallbackText
        # Stripping <think> leaves nothing; we keep the original text so the user sees SOMETHING
        # rather than a blank field. Better UX than silent emptiness.
        $r.analysis | Should Be $content
        $r.risk_level | Should Be 'unknown'
    }
}
