import Image from "next/image";

type BrandLogoProps = {
  width: number;
  height: number;
  alt?: string;
  priority?: boolean;
  className?: string;
};

export function BrandLogo({
  width,
  height,
  alt = "Logotipo de El Pollo Móvil",
  priority = false,
  className,
}: BrandLogoProps) {
  return (
    <Image
      src="/branding/pollo-movil.png"
      alt={alt}
      width={width}
      height={height}
      priority={priority}
      unoptimized
      className={className}
    />
  );
}
