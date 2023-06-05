@{
    Severity     = @('Error', 'Warning')
    # ToDo: Remove excludes after Import-TeamViewerUser was adapted
    ExcludeRules = @('PSUseProcessBlockForPipelineCommand', 'PSAvoidUsingConvertToSecureStringWithPlainText')
}
