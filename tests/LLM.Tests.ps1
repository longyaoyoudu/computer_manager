$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Resolve-Path "$here\..\computer_manager.ps1").Path
. $sut

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
