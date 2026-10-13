import UWP
import WinUI

extension Page {
    var view: UIElement {
        let loaded: Grid = App.context.requireXaml(withString: xamlUI)
        let headerBorder: Border = loaded.requireElement("headerBorder")
        let headerContainer: Border = loaded.requireElement("headerContainer")
        let headerText: TextBlock = loaded.requireElement("headerText")
        let contentBorder: Border = loaded.requireElement("contentBorder")

        if let text = header as? String {
            headerText.text = text
        } else if let view = header as? UIElement {
            headerContainer.child = view
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
             Grid 而非水平 StackPanel：UIElement header 须拉伸占满行宽（页面内部
             才能自行左右分栏），String header 与容器互斥、TextBlock 左起不受影响。 -->
        <Border Name="headerBorder" Grid.Row="0" Margin="32,28,0,28">
            <Grid>
                <Border Name="headerContainer" />
                <TextBlock Name="headerText" Style="{StaticResource TitleTextBlockStyle}"/>
            </Grid>
        </Border>
        <!-- Row 1: Content -->
        <Border Name="contentBorder" Grid.Row="1" />
    </Grid>
    """
}
