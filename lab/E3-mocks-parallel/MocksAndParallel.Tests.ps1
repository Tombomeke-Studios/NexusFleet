# Experiment E3: do Pester mocks reach into ForEach-Object -Parallel runspaces?
# Run: Invoke-Pester -Path ./lab/E3-mocks-parallel -Output Detailed

BeforeAll {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'FleetDemo.psm1') -Force

    # Replace the "outside world" with a fake answer, inside the module where it is called.
    Mock -CommandName Get-DemoAnswer -ModuleName FleetDemo -MockWith { "mock:$Name" }
}

AfterAll {
    Remove-Module -Name FleetDemo -Force -ErrorAction SilentlyContinue
}

Describe 'E3: Pester mocks and ForEach-Object -Parallel' {
    It 'the mock works when the per-host function is called directly' {
        Invoke-DemoHostWork -Name 'host1' | Should -Be 'mock:host1'
        Should -Invoke -CommandName Get-DemoAnswer -ModuleName FleetDemo -Times 1 -Exactly
    }

    It 'the mock works in a sequential loop (same runspace)' {
        Invoke-DemoFleetWorkSequential -Name 'host1', 'host2' | Should -Be @('mock:host1', 'mock:host2')
        Should -Invoke -CommandName Get-DemoAnswer -ModuleName FleetDemo -Times 2 -Exactly
    }

    It 'the mock is NOT used inside ForEach-Object -Parallel: the real function runs' {
        $results = Invoke-DemoFleetWorkParallel -Name 'host1', 'host2', 'host3' | Sort-Object

        $results | Should -Be @('real:host1', 'real:host2', 'real:host3')
        Should -Invoke -CommandName Get-DemoAnswer -ModuleName FleetDemo -Times 0 -Exactly
    }
}
