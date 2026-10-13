import UWP
import WinUI

extension Page {
    var view: UIElement {
        let loaded: Grid = App.context.requireXaml(withString: xamlUI)
        let headerBorder: Border = loaded.requireElement("headerBorder")
        let headerText: TextBlock = loaded.requireElement("headerText")
        let contentBorder: Border = loaded.requireElement("contentBorder")

        if let text = header as? String {
            headerText.text = text
        } else if let view = header as? UIElement {
            headerBorder.child = view
        } else {
            headerBorder.visibility = .collapsed
        }
        contentBorder.child = content

        return loaded
    }
}

private var xamlUI: String {
    """
    <Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Row 0: Header — WinUI default NavigationViewHeaderMargin (56,44,0,0) is too large, use Photos app's (32,28,0,28) instead.
             String header 用 headerText; UIElement header 直挂 headerBorder(整行
             拉伸，页内可左右分栏；嵌套收缩容器会破坏拉伸且曾致 repeater 命中失效) -->
        <Border Name="headerBorder" Grid.Row="0" Margin="32,28,0,28">
            <TextBlock Name="headerText" Style="{StaticResource TitleTextBlockStyle}"/>
        </Border>
        <!-- Row 1: Content -->
        <Border Name="contentBorder" Grid.Row="1" />
    </Grid>
    """
}
