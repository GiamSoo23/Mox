package com.mox.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.mox.app.R

/**
 * Mox brand palette — pulled from the launcher icon. We always run the dark
 * scheme regardless of system theme so the app and the icon read as one
 * piece. Dynamic colors are intentionally disabled.
 */
private val MoxNavy        = Color(0xFF0F172A)
private val MoxNavySoft    = Color(0xFF1E293B)
private val MoxNavyMuted   = Color(0xFF334155)
private val MoxMint        = Color(0xFF5DDFA8)
private val MoxMintDeep    = Color(0xFF1F6B4A)
private val MoxFog         = Color(0xFFE2E8F0)
private val MoxFogMuted    = Color(0xFFCBD5E1)
private val MoxLine        = Color(0xFF475569)
private val MoxDanger      = Color(0xFFEF4444)
private val MoxDangerDeep  = Color(0xFF7F1D1D)

private val MoxColors = darkColorScheme(
    primary            = MoxMint,
    onPrimary          = MoxNavy,
    primaryContainer   = MoxMintDeep,
    onPrimaryContainer = MoxFog,
    secondary          = MoxFog,
    onSecondary        = MoxNavy,
    background         = MoxNavy,
    onBackground       = MoxFog,
    surface            = MoxNavySoft,
    onSurface          = MoxFog,
    surfaceVariant     = MoxNavyMuted,
    onSurfaceVariant   = MoxFogMuted,
    outline            = MoxLine,
    error              = MoxDanger,
    onError            = Color.White,
    errorContainer     = MoxDangerDeep,
    onErrorContainer   = MoxFog,
)

private val Inter = FontFamily(
    Font(R.font.inter_regular,  FontWeight.Normal),
    Font(R.font.inter_medium,   FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
    Font(R.font.inter_bold,     FontWeight.Bold),
)

/**
 * Inter-based type scale with slightly tighter tracking on display sizes,
 * mirroring Wise's geometric, generous feel.
 */
private val MoxTypography = Typography(
    displayLarge   = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Bold,    fontSize = 48.sp, lineHeight = 56.sp, letterSpacing = (-0.5).sp),
    displayMedium  = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Bold,    fontSize = 40.sp, lineHeight = 48.sp, letterSpacing = (-0.4).sp),
    displaySmall   = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold,fontSize = 32.sp, lineHeight = 40.sp, letterSpacing = (-0.3).sp),
    headlineLarge  = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold,fontSize = 28.sp, lineHeight = 36.sp, letterSpacing = (-0.2).sp),
    headlineMedium = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold,fontSize = 24.sp, lineHeight = 32.sp, letterSpacing = (-0.1).sp),
    headlineSmall  = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold,fontSize = 20.sp, lineHeight = 28.sp),
    titleLarge     = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold,fontSize = 18.sp, lineHeight = 26.sp),
    titleMedium    = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium,  fontSize = 16.sp, lineHeight = 24.sp),
    titleSmall     = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium,  fontSize = 14.sp, lineHeight = 20.sp),
    bodyLarge      = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal,  fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium     = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal,  fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall      = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal,  fontSize = 12.sp, lineHeight = 16.sp),
    labelLarge     = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium,  fontSize = 14.sp, lineHeight = 20.sp),
    labelMedium    = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium,  fontSize = 12.sp, lineHeight = 16.sp),
    labelSmall     = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium,  fontSize = 11.sp, lineHeight = 16.sp),
)

@Composable
fun MoxTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = MoxColors,
        typography  = MoxTypography,
        content     = content
    )
}
