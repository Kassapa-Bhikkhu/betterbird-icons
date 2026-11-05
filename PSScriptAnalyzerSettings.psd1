@{
    ExcludeRules = @(
        # The script is an interactive tool: its coloured menu and messages are meant for the console.
        'PSAvoidUsingWriteHost',
        # These rules are for published cmdlets. The helpers here are private to one script,
        # and their plural names (Find-Shortcuts, Get-Profiles) say what they return.
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns'
    )
}
