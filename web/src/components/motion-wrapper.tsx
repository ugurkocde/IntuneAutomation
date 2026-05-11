"use client";

import { type ReactNode } from "react";
import { motion, type MotionProps } from "framer-motion";

interface MotionWrapperProps extends MotionProps {
  children: ReactNode;
  className?: string;
}

export function MotionDiv({ children, ...props }: MotionWrapperProps) {
  return <motion.div {...props}>{children}</motion.div>;
}

export function MotionButton({ children, ...props }: MotionWrapperProps) {
  return <motion.button {...props}>{children}</motion.button>;
}
