<#
    Preview-StatusToasts.ps1
    Shows the Success and Issues toast notifications side by side (sequentially).
    Close each window to advance to the next.
#>
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function Show-DATStatusToast {
    param(
        [string]$Heading,
        [string]$Body,
        [string]$Icon,
        [string]$IconColor,
        [string]$AccentColor,
        [string]$IconBackground
    )

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DAT Toast Preview" Width="420" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent"
        Topmost="True" ResizeMode="NoResize" ShowInTaskbar="True">
    <Border CornerRadius="12" Background="#0F172A" Margin="10"
            BorderBrush="$AccentColor" BorderThickness="1">
        <Border.Effect>
            <DropShadowEffect BlurRadius="20" Opacity="0.5" ShadowDepth="4"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="4"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <!-- Accent strip -->
            <Border Grid.Row="0" CornerRadius="11,11,0,0" Background="$AccentColor"/>
            <!-- Icon + text -->
            <StackPanel Grid.Row="1" HorizontalAlignment="Center" Margin="24,28,24,16">
                <Border Width="68" Height="68" CornerRadius="34" Background="$IconBackground"
                        HorizontalAlignment="Center" Margin="0,0,0,16">
                    <TextBlock Text="$Icon" FontFamily="Segoe MDL2 Assets" FontSize="34"
                               Foreground="$IconColor"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <TextBlock Text="$Heading" FontSize="18" FontWeight="Bold"
                           Foreground="#F8FAFC" HorizontalAlignment="Center"
                           TextAlignment="Center" TextWrapping="Wrap" Margin="0,0,0,10"/>
                <TextBlock TextWrapping="Wrap" FontSize="13" Foreground="#CBD5E1"
                           HorizontalAlignment="Center" TextAlignment="Center"
                           LineHeight="20" MaxWidth="340">$Body</TextBlock>
            </StackPanel>
            <!-- Close Button -->
            <Grid Grid.Row="2" Margin="24,0,24,20">
                <Button x:Name="btnClose" Content="Close"
                        Height="40" Width="160" FontSize="14" FontWeight="SemiBold"
                        HorizontalAlignment="Center"
                        Foreground="#F8FAFC" Cursor="Hand" BorderThickness="0">
                    <Button.Template>
                        <ControlTemplate TargetType="Button">
                            <Border x:Name="bd" CornerRadius="8" Background="#334155" Padding="16,8"
                                    BorderBrush="#475569" BorderThickness="1">
                                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <ControlTemplate.Triggers>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="bd" Property="Background" Value="#475569"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                    </Button.Template>
                </Button>
            </Grid>
        </Grid>
    </Border>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $window.FindName('btnClose').Add_Click({ $window.Close() })
    $window.ShowDialog() | Out-Null
}

# ── Preview 1: Successfully Updated ─────────────────────────────────────────
Show-DATStatusToast `
    -Heading        'Drivers Successfully Updated' `
    -Body           'Your device drivers have been successfully updated. No restart is required unless indicated by your IT department.' `
    -Icon           ([char]0xE930) `
    -IconColor      '#22C55E' `
    -AccentColor    '#16A34A' `
    -IconBackground '#052e16'

# ── Preview 2: Issues Occurred ───────────────────────────────────────────────
Show-DATStatusToast `
    -Heading        'Update Issues Detected' `
    -Body           'One or more driver updates encountered errors during installation. Please contact your IT department or check the device logs for details.' `
    -Icon           ([char]0xE7BA) `
    -IconColor      '#F59E0B' `
    -AccentColor    '#D97706' `
    -IconBackground '#451a03'
