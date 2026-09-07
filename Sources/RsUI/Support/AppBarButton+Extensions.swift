import WinUI

extension AppBarButton {
    public static func makeIconOnly(glyph: String, tooltip: String) -> AppBarButton {
        let ui = xamlUI.replacingOccurrences(of: "{x:Glyph}", with: glyph).replacingOccurrences(of: "{x:ToolTip}", with: tooltip)
        let button: AppBarButton = App.context.requireXaml(withString: ui)
        return button
    }
}

private var xamlUI: String {
    """
    <AppBarButton xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        ToolTipService.ToolTip="{x:ToolTip}">
        <AppBarButton.Resources>
        <!-- The style can make button without padding and corner. -->
        <Style x:Key="AppBarButtonIconOnlyStyle" TargetType="AppBarButton">
            <Setter Property="Width" Value="48"/>
            <Setter Property="LabelPosition" Value="Collapsed"/>
        </Style>
        </AppBarButton.Resources>
        <AppBarButton.Style>
            <StaticResource ResourceKey="AppBarButtonIconOnlyStyle"/>
        </AppBarButton.Style>
        <AppBarButton.Icon>
            <FontIcon Glyph="{x:Glyph}"/>
        </AppBarButton.Icon>
    </AppBarButton>
    """
}
