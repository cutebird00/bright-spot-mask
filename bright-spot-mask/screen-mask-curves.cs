using System;
using System.Windows.Media;

public static class MaskCurves {
    const int Samples=128;
    static double Clamp(double value,double lower,double upper) { return Math.Max(lower,Math.Min(upper,value)); }
    // A shared, shape-preserving tangent. Reversing channels have zero slope at their extremum.
    static double MiddleSlope(double a,double b,double c,double h1,double h2) {
        double s1=(b-a)/h1,s2=(c-b)/h2;
        if(s1==0.0 || s2==0.0 || Math.Sign(s1)!=Math.Sign(s2))return 0.0;
        double w1=2.0*h2+h1,w2=h2+2.0*h1;
        double slope=(w1+w2)/(w1/s1+w2/s2);
        // This bound keeps all six quintic Bezier control values in monotone order.
        double limit=2.5*Math.Min(Math.Abs(s1),Math.Abs(s2));
        return Math.Sign(slope)*Math.Min(Math.Abs(slope),limit);
    }
    static double Segment(double a,double b,double slopeA,double slopeB,double width,double t) {
        if(t<=0.0)return a;
        if(t>=1.0)return b;
        double d=b-a,ma=width*slopeA,mb=width*slopeB;
        // Quintic Hermite: endpoint values/slopes are exact, second derivatives are zero.
        double c3=10.0*d-6.0*ma-4.0*mb;
        double c4=-15.0*d+8.0*ma+7.0*mb;
        double c5=6.0*d-3.0*ma-3.0*mb;
        return Clamp(a+ma*t+t*t*t*(c3+t*(c4+t*c5)),Math.Min(a,b),Math.Max(a,b));
    }
    public static double SampleChannel(double center,double middle,double edge,double middleOffset,double feather,bool enabled,double radius) {
        middleOffset=Clamp(middleOffset,0.01,0.99);feather=Clamp(feather,0.0,1.0);
        double start=enabled ? Math.Min(middleOffset-0.0001,middleOffset*(1.0-feather)) : Math.Min(0.999,1.0-feather);
        start=Math.Max(0.0,start);
        if(radius<=start)return center;
        if(radius>=1.0)return edge;
        if(!enabled)return Segment(center,edge,0.0,0.0,1.0-start,(radius-start)/(1.0-start));
        double h1=middleOffset-start,h2=1.0-middleOffset;
        double slope=MiddleSlope(center,middle,edge,h1,h2);
        if(radius<=middleOffset)return Segment(center,middle,0.0,slope,h1,(radius-start)/h1);
        return Segment(middle,edge,slope,0.0,h2,(radius-middleOffset)/h2);
    }
    static byte ByteValue(double value) { return (byte)Math.Round(Clamp(value,0.0,255.0)); }
    static Color At(Color a,Color b,Color c,double middle,double feather,bool enabled,double radius) {
        return Color.FromArgb(
            ByteValue(SampleChannel(a.A,b.A,c.A,middle,feather,enabled,radius)),
            ByteValue(SampleChannel(a.R,b.R,c.R,middle,feather,enabled,radius)),
            ByteValue(SampleChannel(a.G,b.G,c.G,middle,feather,enabled,radius)),
            ByteValue(SampleChannel(a.B,b.B,c.B,middle,feather,enabled,radius)));
    }
    public static GradientStopCollection Build(Color center,Color middle,Color edge,double middleOffset,double feather,bool enabled) {
        middleOffset=Clamp(middleOffset,0.01,0.99);feather=Clamp(feather,0.0,1.0);
        double start=enabled ? Math.Min(middleOffset-0.0001,middleOffset*(1.0-feather)) : Math.Min(0.999,1.0-feather);
        start=Math.Max(0.0,start);
        var stops=new GradientStopCollection();stops.Add(new GradientStop(center,0.0));
        if(start>0.0)stops.Add(new GradientStop(center,start));
        if(enabled) {
            for(int i=1;i<=Samples;i++) {
                double radius=start+(middleOffset-start)*i/Samples;
                stops.Add(new GradientStop(At(center,middle,edge,middleOffset,feather,true,radius),radius));
            }
            for(int i=1;i<=Samples;i++) {
                double radius=middleOffset+(1.0-middleOffset)*i/Samples;
                stops.Add(new GradientStop(At(center,middle,edge,middleOffset,feather,true,radius),radius));
            }
        } else {
            for(int i=1;i<=Samples;i++) {
                double radius=start+(1.0-start)*i/Samples;
                stops.Add(new GradientStop(At(center,middle,edge,middleOffset,feather,false,radius),radius));
            }
        }
        stops.Freeze();return stops;
    }
}
