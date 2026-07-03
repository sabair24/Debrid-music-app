import javax.imageio.ImageIO;
import java.awt.*;
import java.awt.geom.*;
import java.awt.image.BufferedImage;
import java.io.*;
import java.util.ArrayList;
import java.util.List;

/** Generates a modern DebridMusic app icon: gradient rounded-square + beamed music notes. */
public class IconGen {
    static BufferedImage render(int s) {
        BufferedImage img = new BufferedImage(s, s, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
        g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);

        // Rounded-square background with a diagonal purple -> teal gradient.
        float r = s * 0.23f;
        g.setPaint(new GradientPaint(s * 0.05f, 0, new Color(0x8B5CFF), s * 0.95f, s, new Color(0x00D0C4)));
        g.fill(new RoundRectangle2D.Float(0, 0, s, s, r, r));
        // Subtle top sheen.
        g.setPaint(new GradientPaint(0, 0, new Color(255, 255, 255, 46), 0, s * 0.6f, new Color(255, 255, 255, 0)));
        g.fill(new RoundRectangle2D.Float(0, 0, s, s, r, r));

        // Beamed eighth notes (two heads + stems + slanted beam), in white.
        g.setColor(Color.WHITE);
        double headR = s * 0.115;
        double x1 = s * 0.335, y1 = s * 0.705;
        double x2 = s * 0.635, y2 = s * 0.635;
        g.fill(new Ellipse2D.Double(x1 - headR, y1 - headR, headR * 2, headR * 2));
        g.fill(new Ellipse2D.Double(x2 - headR, y2 - headR, headR * 2, headR * 2));

        double stemW = s * 0.050;
        double topY1 = s * 0.255, topY2 = s * 0.215;
        double sx1 = x1 + headR - stemW, sx2 = x2 + headR - stemW;
        g.fill(new RoundRectangle2D.Double(sx1, topY1, stemW, y1 - topY1, stemW, stemW));
        g.fill(new RoundRectangle2D.Double(sx2, topY2, stemW, y2 - topY2, stemW, stemW));

        // Beam linking the two stem tops.
        g.setStroke(new BasicStroke((float) (s * 0.105), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
        g.draw(new Line2D.Double(sx1 + stemW / 2, topY1 + s * 0.02, sx2 + stemW / 2, topY2 + s * 0.02));
        g.dispose();
        return img;
    }

    public static void main(String[] args) throws Exception {
        String base = args[0];
        int[] sizes = {16, 20, 24, 32, 40, 48, 64, 128, 256};
        List<byte[]> pngs = new ArrayList<>();
        for (int s : sizes) {
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            ImageIO.write(render(s), "png", bo);
            pngs.add(bo.toByteArray());
        }
        File ico = new File(base, "server/build-res/icon.ico");
        ico.getParentFile().mkdirs();
        try (DataOutputStream d = new DataOutputStream(new BufferedOutputStream(new FileOutputStream(ico)))) {
            le16(d, 0); le16(d, 1); le16(d, sizes.length);
            int offset = 6 + sizes.length * 16;
            for (int i = 0; i < sizes.length; i++) {
                int s = sizes[i]; byte[] png = pngs.get(i);
                d.writeByte(s >= 256 ? 0 : s); d.writeByte(s >= 256 ? 0 : s); d.writeByte(0); d.writeByte(0);
                le16(d, 1); le16(d, 32); le32(d, png.length); le32(d, offset);
                offset += png.length;
            }
            for (byte[] png : pngs) d.write(png);
        }
        // PNGs for the tray + web favicon.
        File png256 = new File(base, "server/src/main/resources/webui/logo.png");
        png256.getParentFile().mkdirs();
        ImageIO.write(render(256), "png", png256);
        ImageIO.write(render(512), "png", new File(base, "server/build-res/icon-512.png"));
        System.out.println("wrote " + ico.getAbsolutePath());
    }

    static void le16(DataOutputStream d, int v) throws IOException { d.writeByte(v & 0xFF); d.writeByte((v >> 8) & 0xFF); }
    static void le32(DataOutputStream d, int v) throws IOException {
        d.writeByte(v & 0xFF); d.writeByte((v >> 8) & 0xFF); d.writeByte((v >> 16) & 0xFF); d.writeByte((v >> 24) & 0xFF);
    }
}
